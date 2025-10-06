// SDRAM controller tailored for the DE2-115 board (Cyclone IV + 16-bit SDR SDRAM)
// Provides a simple single-transaction command interface with automatic refresh.

module sdram_controller #(
    parameter integer DATA_WIDTH = 16,
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer INIT_DELAY_US = 200,
    parameter integer REFRESH_INTERVAL_NS = 7800,
    parameter integer SDRAM_ROW_WIDTH = 13,
    parameter integer SDRAM_COL_WIDTH = 9,
    parameter integer SDRAM_BANK_WIDTH = 2,
    parameter integer SDRAM_ADDR_WIDTH = 13,
    parameter integer AUTO_PRECHARGE_BIT = 10,
    parameter integer CAS_LATENCY = 3,
    parameter integer TRCD_CYCLES = 3,
    parameter integer TRP_CYCLES = 3,
    parameter integer TRFC_CYCLES = 7,
    parameter integer TWR_CYCLES = 3
) (
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         cmd_valid,
    input  wire                         cmd_write,
    input  wire [SDRAM_ROW_WIDTH + SDRAM_COL_WIDTH + SDRAM_BANK_WIDTH - 1:0] cmd_addr,
    input  wire [DATA_WIDTH-1:0]        cmd_wdata,
    input  wire [DATA_WIDTH/8-1:0]      cmd_mask,
    output reg                          cmd_ready,
    output reg  [DATA_WIDTH-1:0]        rd_data,
    output reg                          rd_data_valid,
    output wire                         busy,
    // output wire                         sdram_clk, // This is now just the internal clock
    output reg                          sdram_cke,
    output reg                          sdram_cs_n,
    output reg                          sdram_ras_n,
    output reg                          sdram_cas_n,
    output reg                          sdram_we_n,
    output reg  [SDRAM_ADDR_WIDTH-1:0]  sdram_addr,
    output reg  [SDRAM_BANK_WIDTH-1:0]  sdram_ba,
    output reg  [DATA_WIDTH/8-1:0]      sdram_dqm,
    inout  wire [DATA_WIDTH-1:0]        sdram_dq
);

    localparam integer BYTE_COUNT = DATA_WIDTH / 8;
    localparam integer ADDR_WIDTH = SDRAM_ROW_WIDTH + SDRAM_COL_WIDTH + SDRAM_BANK_WIDTH;
    localparam integer CLK_MHZ = (CLK_FREQ_HZ / 1_000_000);
    localparam integer INIT_CYCLES = (CLK_MHZ * INIT_DELAY_US) > 0 ? (CLK_MHZ * INIT_DELAY_US) : 1;
    localparam integer REFRESH_CYCLES = ((CLK_MHZ * REFRESH_INTERVAL_NS) / 1000);
    localparam integer REFRESH_CYCLES_SAFE = (REFRESH_CYCLES > 0) ? REFRESH_CYCLES : 1;

    localparam [SDRAM_ADDR_WIDTH-1:0] MODE_REGISTER = {
        {(SDRAM_ADDR_WIDTH-13){1'b0}}, // upper bits if wider than 13
        3'b000,                        // A12:A10 reserved
        1'b0,                          // A9  = 0 -> burst length by A[2:0]
        2'b00,                         // A8:A7 = 0 -> standard operation
        3'b011,                        // A6:A4 = 3 -> CAS latency = 3
        1'b0,                          // A3 = 0 -> sequential burst
        3'b000                         // A2:A0 = 0 -> burst length = 1
    };

    localparam integer COL_LSB  = 0;
    localparam integer COL_MSB  = SDRAM_COL_WIDTH - 1;
    localparam integer BANK_LSB = SDRAM_COL_WIDTH;
    localparam integer BANK_MSB = SDRAM_COL_WIDTH + SDRAM_BANK_WIDTH - 1;
    localparam integer ROW_LSB  = SDRAM_COL_WIDTH + SDRAM_BANK_WIDTH;
    localparam integer ROW_MSB  = SDRAM_COL_WIDTH + SDRAM_BANK_WIDTH + SDRAM_ROW_WIDTH - 1;

    // assign sdram_clk = clk; // No longer needed, clk is the internal clock
    assign busy = ~cmd_ready;

    wire [DATA_WIDTH-1:0] dq_in;
    reg  [DATA_WIDTH-1:0] dq_out;
    reg                   dq_oe;

    assign sdram_dq = dq_oe ? dq_out : {DATA_WIDTH{1'bz}};
    assign dq_in = sdram_dq;

    localparam [4:0] ST_RESET               = 5'd0;
    localparam [4:0] ST_INIT_WAIT           = 5'd1;
    localparam [4:0] ST_CKE_ENABLE          = 5'd2;
    localparam [4:0] ST_PRECHARGE_ALL       = 5'd3;
    localparam [4:0] ST_PRECHARGE_WAIT      = 5'd4;
    localparam [4:0] ST_AUTO_REFRESH_1      = 5'd5;
    localparam [4:0] ST_AUTO_REFRESH_1_WAIT = 5'd6;
    localparam [4:0] ST_AUTO_REFRESH_2      = 5'd7;
    localparam [4:0] ST_AUTO_REFRESH_2_WAIT = 5'd8;
    localparam [4:0] ST_MODE_REGISTER       = 5'd9;
    localparam [4:0] ST_MODE_REGISTER_WAIT  = 5'd10;
    localparam [4:0] ST_IDLE                = 5'd11;
    localparam [4:0] ST_ACTIVATE            = 5'd12;
    localparam [4:0] ST_ACTIVATE_WAIT       = 5'd13;
    localparam [4:0] ST_READ                = 5'd14;
    localparam [4:0] ST_READ_WAIT           = 5'd15;
    localparam [4:0] ST_READ_CAPTURE        = 5'd16;
    localparam [4:0] ST_READ_POST           = 5'd17;
    localparam [4:0] ST_WRITE               = 5'd18;
    localparam [4:0] ST_WRITE_WAIT          = 5'd19;
    localparam [4:0] ST_WRITE_DATA          = 5'd20;
    localparam [4:0] ST_WRITE_POST          = 5'd21;
    localparam [4:0] ST_REFRESH             = 5'd22;
    localparam [4:0] ST_REFRESH_WAIT        = 5'd23;

    reg [4:0] state;
    reg [15:0] wait_counter;
    reg [4:0]  cas_counter;
    reg [31:0] init_counter;
    reg [ADDR_WIDTH-1:0] latched_addr;
    reg                  latched_write;
    reg [DATA_WIDTH-1:0] latched_wdata;
    reg [BYTE_COUNT-1:0] latched_mask;
    reg                  init_done;
    reg [15:0]           refresh_counter;
    reg                  refresh_request;

    wire [SDRAM_COL_WIDTH-1:0]  current_col  = latched_addr[COL_MSB:COL_LSB];
    wire [SDRAM_BANK_WIDTH-1:0] current_bank = latched_addr[BANK_MSB:BANK_LSB];
    wire [SDRAM_ROW_WIDTH-1:0]  current_row  = latched_addr[ROW_MSB:ROW_LSB];

    function [SDRAM_ADDR_WIDTH-1:0] row_address;
        input [SDRAM_ROW_WIDTH-1:0] row;
        reg   [SDRAM_ADDR_WIDTH-1:0] tmp;
    begin
        tmp = {SDRAM_ADDR_WIDTH{1'b0}};
        tmp[SDRAM_ROW_WIDTH-1:0] = row;
        row_address = tmp;
    end
    endfunction

    function [SDRAM_ADDR_WIDTH-1:0] column_address;
        input [SDRAM_COL_WIDTH-1:0] column;
        input                        autoprecharge;
        reg   [SDRAM_ADDR_WIDTH-1:0] tmp;
    begin
        tmp = {SDRAM_ADDR_WIDTH{1'b0}};
        tmp[SDRAM_COL_WIDTH-1:0] = column;
        if (AUTO_PRECHARGE_BIT < SDRAM_ADDR_WIDTH) begin
            tmp[AUTO_PRECHARGE_BIT] = autoprecharge;
        end
        column_address = tmp;
    end
    endfunction

    initial begin
        if (DATA_WIDTH % 8 != 0) begin
            $error("sdram_controller: DATA_WIDTH must be a multiple of 8");
        end
        if (SDRAM_ADDR_WIDTH <= AUTO_PRECHARGE_BIT) begin
            $error("sdram_controller: AUTO_PRECHARGE_BIT must be less than SDRAM_ADDR_WIDTH");
        end
        if (CLK_MHZ == 0) begin
            $error("sdram_controller: CLK_FREQ_HZ must be >= 1 MHz");
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= ST_RESET;
            sdram_cke        <= 1'b0;
            sdram_cs_n       <= 1'b1;
            sdram_ras_n      <= 1'b1;
            sdram_cas_n      <= 1'b1;
            sdram_we_n       <= 1'b1;
            sdram_addr       <= {SDRAM_ADDR_WIDTH{1'b0}};
            sdram_ba         <= {SDRAM_BANK_WIDTH{1'b0}};
            sdram_dqm        <= {BYTE_COUNT{1'b1}};
            cmd_ready        <= 1'b0;
            rd_data          <= {DATA_WIDTH{1'b0}};
            rd_data_valid    <= 1'b0;
            dq_out           <= {DATA_WIDTH{1'b0}};
            dq_oe            <= 1'b0;
            wait_counter     <= 16'd0;
            cas_counter      <= 5'd0;
            init_counter     <= INIT_CYCLES[31:0];
            latched_addr     <= {ADDR_WIDTH{1'b0}};
            latched_write    <= 1'b0;
            latched_wdata    <= {DATA_WIDTH{1'b0}};
            latched_mask     <= {BYTE_COUNT{1'b0}};
            init_done        <= 1'b0;
            refresh_counter  <= 16'd0;
            refresh_request  <= 1'b0;
        end else begin
            // Default outputs for NOP
            sdram_cs_n    <= 1'b0;
            sdram_ras_n   <= 1'b1;
            sdram_cas_n   <= 1'b1;
            sdram_we_n    <= 1'b1;
            sdram_addr    <= {SDRAM_ADDR_WIDTH{1'b0}};
            sdram_ba      <= {SDRAM_BANK_WIDTH{1'b0}};
            sdram_dqm     <= {BYTE_COUNT{1'b0}};
            dq_oe         <= 1'b0;
            rd_data_valid <= 1'b0;
            cmd_ready     <= 1'b0;

            case (state)
                ST_RESET: begin
                    sdram_cke    <= 1'b0;
                    sdram_cs_n   <= 1'b1;
                    sdram_ras_n  <= 1'b1;
                    sdram_cas_n  <= 1'b1;
                    sdram_we_n   <= 1'b1;
                    init_counter <= INIT_CYCLES[31:0];
                    state        <= ST_INIT_WAIT;
                end

                ST_INIT_WAIT: begin
                    sdram_cke <= 1'b0;
                    if (init_counter != 0) begin
                        init_counter <= init_counter - 1;
                    end else begin
                        state <= ST_CKE_ENABLE;
                    end
                end

                ST_CKE_ENABLE: begin
                    sdram_cke <= 1'b1;
                    state     <= ST_PRECHARGE_ALL;
                end

                ST_PRECHARGE_ALL: begin
                    sdram_ras_n <= 1'b0;
                    sdram_we_n  <= 1'b0;
                    if (AUTO_PRECHARGE_BIT < SDRAM_ADDR_WIDTH) begin
                        sdram_addr[AUTO_PRECHARGE_BIT] <= 1'b1;
                    end
                    wait_counter <= (TRP_CYCLES > 0) ? (TRP_CYCLES - 1) : 0;
                    state        <= ST_PRECHARGE_WAIT;
                end

                ST_PRECHARGE_WAIT: begin
                    if (wait_counter == 0) begin
                        state <= ST_AUTO_REFRESH_1;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                ST_AUTO_REFRESH_1: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_we_n  <= 1'b1;
                    wait_counter <= (TRFC_CYCLES > 0) ? (TRFC_CYCLES - 1) : 0;
                    state        <= ST_AUTO_REFRESH_1_WAIT;
                end

                ST_AUTO_REFRESH_1_WAIT: begin
                    if (wait_counter == 0) begin
                        state <= ST_AUTO_REFRESH_2;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                ST_AUTO_REFRESH_2: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_we_n  <= 1'b1;
                    wait_counter <= (TRFC_CYCLES > 0) ? (TRFC_CYCLES - 1) : 0;
                    state        <= ST_AUTO_REFRESH_2_WAIT;
                end

                ST_AUTO_REFRESH_2_WAIT: begin
                    if (wait_counter == 0) begin
                        state <= ST_MODE_REGISTER;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                ST_MODE_REGISTER: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_we_n  <= 1'b0;
                    sdram_addr  <= MODE_REGISTER;
                    wait_counter <= (TRP_CYCLES > 0) ? (TRP_CYCLES - 1) : 0;
                    state        <= ST_MODE_REGISTER_WAIT;
                end

                ST_MODE_REGISTER_WAIT: begin
                    if (wait_counter == 0) begin
                        state       <= ST_IDLE;
                        init_done   <= 1'b1;
                        refresh_counter <= 16'd0;
                        refresh_request <= 1'b0;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                ST_IDLE: begin
                    if (refresh_request) begin
                        cmd_ready <= 1'b0;
                        state     <= ST_REFRESH;
                    end else begin
                        cmd_ready <= 1'b1;
                        if (cmd_valid) begin
                            cmd_ready     <= 1'b0;
                            latched_addr  <= cmd_addr;
                            latched_write <= cmd_write;
                            latched_wdata <= cmd_wdata;
                            latched_mask  <= cmd_mask;
                            state         <= ST_ACTIVATE;
                        end
                    end
                end

                ST_ACTIVATE: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b1;
                    sdram_we_n  <= 1'b1;
                    sdram_ba    <= current_bank;
                    sdram_addr  <= row_address(current_row);
                    wait_counter <= (TRCD_CYCLES > 0) ? (TRCD_CYCLES - 1) : 0;
                    state        <= ST_ACTIVATE_WAIT;
                end

                ST_ACTIVATE_WAIT: begin
                    if (wait_counter == 0) begin
                        state <= latched_write ? ST_WRITE : ST_READ;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                ST_READ: begin
                    sdram_cas_n <= 1'b0;
                    sdram_we_n  <= 1'b1;
                    sdram_ba    <= current_bank;
                    sdram_addr  <= column_address(current_col, 1'b1);
                    // Wait for CAS Latency minus 1 cycle
                    cas_counter <= (CAS_LATENCY > 1) ? (CAS_LATENCY - 1) : 1;
                    state       <= ST_READ_WAIT;
                end

                ST_READ_WAIT: begin
                    if (cas_counter > 1) begin
                        cas_counter <= cas_counter - 1;
                    end else begin
                        // Data is now available on the bus, capture it on the next edge
                        state <= ST_READ_CAPTURE;
                    end
                end

                ST_READ_CAPTURE: begin
                        rd_data       <= dq_in;
                        rd_data_valid <= 1'b1;
                        wait_counter  <= (TRP_CYCLES > 0) ? (TRP_CYCLES - 1) : 0;
                        state         <= ST_READ_POST;
                end

                ST_READ_POST: begin
                    if (wait_counter == 0) begin
                        state <= ST_IDLE;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                ST_WRITE: begin
                    sdram_cas_n <= 1'b0;
                    sdram_we_n  <= 1'b0;
                    sdram_ba    <= current_bank;
                    sdram_addr  <= column_address(current_col, 1'b1);
                    sdram_dqm   <= latched_mask;
                    // Wait 1 cycle before driving the data bus
                    state       <= ST_WRITE_WAIT;
                end

                ST_WRITE_WAIT: begin
                    // Now, drive the data bus
                    state <= ST_WRITE_DATA;
                end

                ST_WRITE_DATA: begin
                    dq_out      <= latched_wdata;
                    dq_oe       <= 1'b1;
                    sdram_dqm   <= latched_mask;
                    wait_counter <= ((TWR_CYCLES + TRP_CYCLES) > 0) ? ((TWR_CYCLES + TRP_CYCLES) - 1) : 0;
                    state        <= ST_WRITE_POST;
                end

                ST_WRITE_POST: begin
                    if (wait_counter == 0) begin
                        state <= ST_IDLE;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                ST_REFRESH: begin
                    sdram_ras_n <= 1'b0;
                    sdram_cas_n <= 1'b0;
                    sdram_we_n  <= 1'b1;
                    wait_counter <= (TRFC_CYCLES > 0) ? (TRFC_CYCLES - 1) : 0;
                    state        <= ST_REFRESH_WAIT;
                    refresh_counter <= 16'd0;
                end

                ST_REFRESH_WAIT: begin
                    if (wait_counter == 0) begin
                        refresh_request <= 1'b0;
                        state           <= ST_IDLE;
                    end else begin
                        wait_counter <= wait_counter - 1;
                    end
                end

                default: begin
                    state <= ST_RESET;
                end
            endcase

            if (!init_done) begin
                refresh_counter <= 16'd0;
                refresh_request <= 1'b0;
            end else if (!refresh_request && state != ST_REFRESH && state != ST_REFRESH_WAIT) begin
                if (refresh_counter >= (REFRESH_CYCLES_SAFE - 1)) begin
                    refresh_counter <= 16'd0;
                    refresh_request <= 1'b1;
                end else begin
                    refresh_counter <= refresh_counter + 1'b1;
                end
            end
        end
    end

endmodule
