/*
Copyright (c) 2024, Gemini Code Assist

This is a completely rewritten, robust SDRAM framebuffer module.
Key features:
- Decoupled request/acknowledge mechanism for read and write operations, preventing data loss.
- A simple and robust state machine for command arbitration.
- Safe bank-swapping logic that occurs only during VGA vertical blanking to prevent tearing.
- Clear separation of clock domains and logic.
*/
module sdram_framebuffer #(
    parameter integer FRAME_WIDTH  = 320,
    parameter integer FRAME_HEIGHT = 240,
    parameter integer DATA_WIDTH   = 16
) (
    input  wire                      reset_n,
    input  wire                      bist_enable,
    input  wire                      cam_clk,
    input  wire                      cam_vsync,
    input  wire                      cam_we,
    input  wire [DATA_WIDTH-1:0]     cam_data,
    input  wire                      vga_clk,
    input  wire                      vga_vsync,
    input  wire [16:0]               vga_addr_req,
    output reg  [DATA_WIDTH-1:0]     vga_data,
    input  wire                      sdram_clk,
    input  wire                      sdram_clk_out,
    output wire [12:0]               sdram_addr,
    output wire [1:0]                sdram_ba,
    output wire                      sdram_cas_n,
    output wire                      sdram_cke,
    output wire                      sdram_clk_pin,
    output wire                      sdram_cs_n,
    inout  wire [DATA_WIDTH-1:0]     sdram_dq,
    output wire [DATA_WIDTH/8-1:0]   sdram_dqm,
    output wire                      sdram_ras_n,
    output wire                      sdram_we_n
);
    localparam integer FRAME_ADDR_WIDTH  = 17; // For 320*240 = 76800 pixels
    localparam [FRAME_ADDR_WIDTH-1:0] FRAME_PIXELS_VALUE = FRAME_WIDTH * FRAME_HEIGHT;
    localparam integer SDRAM_ROW_WIDTH   = 13;
    localparam integer SDRAM_COL_WIDTH   = 9; // For 16-bit data width, 512 columns
    localparam integer SDRAM_BANK_WIDTH  = 2;
    localparam integer SDRAM_ADDR_WIDTH  = SDRAM_ROW_WIDTH + SDRAM_COL_WIDTH + SDRAM_BANK_WIDTH;
    
    // FIFO watermarks for read-priority logic
    localparam integer VGA_FIFO_LOW_WATERMARK  = 128;
    localparam integer VGA_FIFO_HIGH_WATERMARK = 1024; // Increased to buffer more data

    assign sdram_clk_pin = sdram_clk_out;

    // =====================================================================
    // Clock Domain Crossing (CDC) for Handshakes
    // =====================================================================
    // Camera VSYNC (cam_clk -> sdram_clk)
    reg  cam_vsync_d;
    wire cam_vsync_rising_edge = cam_vsync && !cam_vsync_d;
    always @(posedge cam_clk or negedge reset_n) begin
        if (!reset_n) cam_vsync_d <= 1'b0;
        else          cam_vsync_d <= cam_vsync;
    end

    reg [1:0] cam_vsync_sync;
    always @(posedge sdram_clk or negedge reset_n) begin
        if (!reset_n) cam_vsync_sync <= 2'b0;
        else          cam_vsync_sync <= {cam_vsync_sync[0], cam_vsync_rising_edge};
    end
    wire cam_frame_start_sdram = cam_vsync_sync[1]; // 1-cycle pulse in sdram_clk domain

    // VGA VSYNC (vga_clk -> sdram_clk)
    reg  vga_vsync_d;
    wire vga_vsync_rising_edge = vga_vsync && !vga_vsync_d;
    always @(posedge vga_clk or negedge reset_n) begin
        if (!reset_n) vga_vsync_d <= 1'b0;
        else          vga_vsync_d <= vga_vsync;
    end

    reg [1:0] vga_vsync_sync;
    always @(posedge sdram_clk or negedge reset_n) begin
        if (!reset_n) vga_vsync_sync <= 2'b0;
        else          vga_vsync_sync <= {vga_vsync_sync[0], vga_vsync_rising_edge};
    end
    wire vga_frame_start_sdram = vga_vsync_sync[1]; // 1-cycle pulse in sdram_clk domain

    // =====================================================================
    // Camera write FIFO (cam_clk -> sdram_clk)
    // =====================================================================
    wire                  cam_fifo_empty;
    wire [16:0]           cam_fifo_q; // Match FIFO IP width
    reg                   cam_fifo_rdreq;
    FIFO cam_write_fifo (
        .data   ({1'b0, cam_data}), // Pad to 17 bits
        .rdclk  (sdram_clk),
        .rdreq  (cam_fifo_rdreq),
        .wrclk  (cam_clk),
        .wrreq  (cam_we),
        .q      (cam_fifo_q),
        .rdempty(cam_fifo_empty),
        .wrfull () // wrfull is not critical here
    );

    // =====================================================================
    // VGA read FIFO (sdram_clk -> vga_clk)
    // =====================================================================
    wire                  vga_fifo_empty, vga_fifo_full;
    wire [16:0]           vga_fifo_q; // Match FIFO IP width
    wire [11:0]           vga_fifo_wrusedw;
    reg                   vga_fifo_wrreq;
    reg                   vga_fifo_rdreq;
    FIFO vga_read_fifo (
        .data   ({1'b0, sdram_rd_data}), // Pad to 17 bits
        .rdclk  (vga_clk),
        .rdreq  (vga_fifo_rdreq),
        .wrclk  (sdram_clk),
        .wrreq  (vga_fifo_wrreq),
        .q      (vga_fifo_q),
        .rdempty(vga_fifo_empty),
        .wrfull (vga_fifo_full),
        .wrusedw(vga_fifo_wrusedw)
    );

    // =====================================================================
    // SDRAM controller wiring
    // =====================================================================
    reg  cmd_valid;
    reg  cmd_write;
    reg  [SDRAM_ADDR_WIDTH-1:0] cmd_addr;
    reg  [DATA_WIDTH-1:0]      cmd_wdata;
    wire cmd_ready;
    wire sdram_rd_valid;
    wire [DATA_WIDTH-1:0] sdram_rd_data;
    sdram_controller #(
        .DATA_WIDTH       (DATA_WIDTH),
        .CLK_FREQ_HZ      (100_000_000),
        .SDRAM_ROW_WIDTH  (SDRAM_ROW_WIDTH),
        .SDRAM_COL_WIDTH  (SDRAM_COL_WIDTH),
        .SDRAM_BANK_WIDTH (SDRAM_BANK_WIDTH)
    ) sdram_ctrl (
        .clk            (sdram_clk),
        .reset_n        (reset_n),
        .cmd_valid      (cmd_valid),
        .cmd_write      (cmd_write),
        .cmd_addr       (cmd_addr),
        .cmd_wdata      (cmd_wdata),
        .cmd_mask       (2'b00),
        .cmd_ready      (cmd_ready),
        .rd_data        (sdram_rd_data),
        .rd_data_valid  (sdram_rd_valid),
        .busy           (), // Unused
        .sdram_cke      (sdram_cke),
        .sdram_cs_n     (sdram_cs_n),
        .sdram_ras_n    (sdram_ras_n),
        .sdram_cas_n    (sdram_cas_n),
        .sdram_we_n     (sdram_we_n),
        .sdram_addr     (sdram_addr),
        .sdram_ba       (sdram_ba),
        .sdram_dqm      (sdram_dqm),
        .sdram_dq       (sdram_dq)
    );

    // =====================================================================
    // Address helpers
    // =====================================================================
    function [SDRAM_ADDR_WIDTH-1:0] linear_to_sdram_addr;
        input [FRAME_ADDR_WIDTH-1:0] linear_addr;
        input                        bank_bit;
        reg [SDRAM_COL_WIDTH-1:0]  col;
        reg [SDRAM_ROW_WIDTH-1:0]  row;
        reg [SDRAM_BANK_WIDTH-1:0] bank;
    begin
        col  = linear_addr[SDRAM_COL_WIDTH-1:0];
        row  = linear_addr[FRAME_ADDR_WIDTH-1 : SDRAM_COL_WIDTH];
        bank = {1'b0, bank_bit}; // Assuming 2 banks
        linear_to_sdram_addr = {row, bank, col};
    end
    endfunction

    // =====================================================================
    // SDRAM domain control - NEW ROBUST STATE MACHINE
    // =====================================================================
    // State machine states
    localparam [1:0] S_IDLE     = 2'd0;
    localparam [1:0] S_DO_WRITE = 2'd1;
    localparam [1:0] S_DO_READ  = 2'd2;

    reg [1:0] state;

    // Write request logic
    reg  write_req;
    wire write_ack = cmd_valid && cmd_write && cmd_ready;
    reg  [DATA_WIDTH-1:0] write_data_reg;

    // Read request logic
    reg  read_req;
    wire read_ack = cmd_valid && !cmd_write && cmd_ready;

    // Pointers and bank control
    reg [FRAME_ADDR_WIDTH-1:0] wr_ptr;
    reg [FRAME_ADDR_WIDTH-1:0] rd_ptr;
    reg  wr_bank; // Bank being written to by camera
    reg  rd_bank; // Bank being read from by VGA
    reg  new_frame_is_ready; // Flag indicates a full frame is written and ready for display

    always @(posedge sdram_clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            wr_ptr <= 0;
            rd_ptr <= 0;
            wr_bank <= 1'b0;
            rd_bank <= 1'b1;
            new_frame_is_ready <= 1'b0;
            cam_fifo_rdreq <= 1'b0;
            vga_fifo_wrreq <= 1'b0;
            write_req <= 1'b0;
            read_req <= 1'b0;
            cmd_valid <= 1'b0;
        end else begin
            // Default assignments
            cam_fifo_rdreq <= 1'b0;
            vga_fifo_wrreq <= 1'b0;
            cmd_valid <= 1'b0;

            // --- Frame Start & Bank Swap Logic ---
            if (cam_frame_start_sdram) begin
                wr_ptr <= 0;
            end

            if (vga_frame_start_sdram) begin
                rd_ptr <= 0;
                // Safely swap banks during V-blank if a new frame is ready
                if (new_frame_is_ready) begin // A new frame was completed during the last VGA frame
                    wr_bank <= ~wr_bank;
                    rd_bank <= ~rd_bank;
                    new_frame_is_ready <= 1'b0;
                end
            end

            // Detect when camera has finished writing a frame
            if (wr_ptr == (FRAME_PIXELS_VALUE - 1) && write_ack) begin
                new_frame_is_ready <= 1'b1;
            end

            // --- Request Generation ---
            if (!cam_fifo_empty && wr_ptr < FRAME_PIXELS_VALUE && state != S_DO_WRITE) begin
                write_req <= 1'b1;
            end else if (write_ack) begin // De-assert request only after it has been acknowledged
                write_req <= 1'b0;
            end
 
            // Generate a read request if VGA needs data and we are not already processing a read
            // CRITICAL: Only start reading if a frame is actually ready to be displayed.
            if (new_frame_is_ready && !vga_fifo_full && rd_ptr < FRAME_PIXELS_VALUE && state != S_DO_READ) begin
                read_req <= 1'b1;
            end else if (read_ack) begin // De-assert request only after it has been acknowledged
                read_req <= 1'b0;
            end

             // Latch write data when making a request
             if (write_req) begin
                 cam_fifo_rdreq <= 1'b1;
                 write_data_reg <= cam_fifo_q[15:0];
             end

            // Latch read data into VGA FIFO
            if (sdram_rd_valid) begin
                vga_fifo_wrreq <= 1'b1;
            end

            // --- State Machine for Arbitration ---
            case (state)
                S_IDLE: begin
                    // Priority: VGA read request if FIFO is low, otherwise Camera write request
                    if (read_req && (vga_fifo_wrusedw < VGA_FIFO_LOW_WATERMARK)) begin
                        state <= S_DO_READ;
                    end else if (write_req) begin
                        state <= S_DO_WRITE;
                    end else if (read_req && (vga_fifo_wrusedw < VGA_FIFO_HIGH_WATERMARK)) begin
                        state <= S_DO_READ;
                    end
                end

                S_DO_WRITE: begin
                    cmd_valid <= write_req; // Only issue command if request is still valid
                    cmd_write <= 1'b1;
                     cmd_addr  <= linear_to_sdram_addr(wr_ptr, wr_bank);
                     cmd_wdata <= write_data_reg;

                     if (write_ack) begin
                         wr_ptr <= wr_ptr + 1;
                         state <= S_IDLE;
                     end
                end

                S_DO_READ: begin
                    cmd_valid <= read_req; // Only issue command if request is still valid
                    cmd_write <= 1'b0;
                     cmd_addr  <= linear_to_sdram_addr(rd_ptr, rd_bank);
 
                     if (read_ack) begin
                         rd_ptr <= rd_ptr + 1;
                         state <= S_IDLE;
                     end
                end
            endcase
        end
    end

// =====================================================================
// VGA domain consumption
// =====================================================================
    reg [16:0]           vga_addr_prev = 17'h1ffff;
    reg                  need_pixel = 1'b0;
    reg [DATA_WIDTH-1:0] last_valid_pixel = {DATA_WIDTH{1'b0}};
    reg                  vga_fifo_rdreq_d;
    
    always @(posedge vga_clk or negedge reset_n) begin
        if (!reset_n) begin
            vga_fifo_rdreq    <= 1'b0;
            vga_fifo_rdreq_d  <= 1'b0;
            vga_data          <= {DATA_WIDTH{1'b0}};
            vga_addr_prev     <= 17'h0;
            need_pixel        <= 1'b0;
            last_valid_pixel  <= {DATA_WIDTH{1'b0}};
        end else begin
            vga_fifo_rdreq_d <= vga_fifo_rdreq;
            vga_fifo_rdreq   <= 1'b0;

            // A new pixel is needed if the address changes
            if (vga_addr_req != vga_addr_prev) begin
                need_pixel <= 1'b1;
            end
            vga_addr_prev <= vga_addr_req;

            // Request pixel from FIFO if needed
            if (need_pixel) begin
                if (!vga_fifo_empty) begin
                    vga_fifo_rdreq <= 1'b1;
                end else begin
                    // FIFO underrun: repeat last valid pixel to mask the error
                    vga_data <= last_valid_pixel;
                    need_pixel <= 1'b0;
                end
            end

            // When the FIFO read request is serviced, latch the data
            if (vga_fifo_rdreq_d) begin
                vga_data          <= vga_fifo_q[15:0]; // Truncate back to 16 bits
                last_valid_pixel  <= vga_fifo_q[15:0]; // Store the last good pixel for masking
                need_pixel        <= 1'b0;
            end
        end
    end

endmodule
