// Read buffer 2 content, which stores taken snapshot (if display
// snapshot button has been pressed), and apply Sobel filter for edge
// detection; write back into buffer 2 the B&W image;
// Note: this is the design entity in this whole project that is
// the trickiest; read comments throughout to get an idea about
// different aspects;
// Note: be aware of some hard coded numbers related to 320x240 here;
// you need to change those for other screen sizes;

module do_edge_detection(
    // controls
    input rst_i,
    input clk_i, // 25 MHz
    input enable_sobel_filter, // start new edge detection
    output reg led_sobel_done, // done this frame
    // connections from frame buffer 2 from where we
    // need to read image data (i.e., gray image) and to which
    // we must apply Sobel filter; we need here to generate "read" addresses;
    output [16:0] rdaddr_buf1,
    input [11:0] din_buf1,
    // connections to frame buffer 2 for which we need to
    // generate "write" addresses and pass pixel data after Sobel edge detection processing;
    output [16:0] wraddr_buf2,
    output [11:0] dout_buf2,
    output reg we_buf2
);

    // State machine states
    localparam [2:0]
        START_SOBEL_FILTER_ST = 3'b000,
        GET_PIXEL_DATA_ST = 3'b001,
        STALL_1_CYCLE_ST = 3'b010,
        STALL_2_CYCLE_ST = 3'b011,
        SEND_PIXEL_DATA_ST = 3'b100,
        DONE_ST = 3'b101,
        IDLE_ST = 3'b110;

    // We need to read 320x240 = 76800 locations
    localparam [16:0] NUM_PIXELS = 17'd76799;

    // Signal that edge detection for whole frame is done
    // (led_sobel_done is used directly)

    // Coming from buffer 2, regular pixel data
    reg [16:0] rdaddr_buf1_r = 17'b0;
    reg [7:0] din_buf1_r;

    // Going to buffer 2, B&W pixels data
    reg [16:0] wraddr_buf2_r = 17'b0;
    reg [7:0] dout_buf2_r = 8'b0;

    // Counter of pixels while reading from buf2
    reg [16:0] rd_cntr = 17'b0;

    // Counter of pixels while writing back into buf2
    // we need this second counter because we must start writing back pixel
    // id 0 right after we just fetched and processed pixel id 1 from second
    // row (that is pixel number 321 for our case of 320x240 frame);
    reg [16:0] wr_cntr = 17'b0;

    // State of the FSM that implements the read or write steps
    reg [2:0] state = IDLE_ST;

    // Note: in current implementation, I actually do not use the delayed
    // sync signals because I use the Sobel filter only once on the taken
    // and displayed and grayed image; however, when applying Sobel filter in
    // video mode, we'll use them;
    // also, because we use it once only and not in video mode - where we
    // have the hsync and vsync signals generated - we need to generate
    // "dummy" hsync and vsync signals, which are used inside edge_sobel_wrapper;
    reg hsync_dummy = 1'b0;
    reg vsync_dummy = 1'b0;
    reg hsync_delayed, vsync_delayed;
    reg [8:0] ColsCounter = 9'b0;
    reg clk_div2 = 1'b0;

    // led_sobel_done is assigned in always block
    assign rdaddr_buf1 = rdaddr_buf1_r;

    // Note: we work for now with gray images; so, just take the 4 bits corresponding to
    // the B channel and use them (concatenate with zeros or itself to "make up"
    // 8 bits that the Sobel filter consumes for each processed pixel);
    // they contain the same info as bits 7:4 or 11:8 in gray images;
    // equivalent of shifting to right by 4 bits; to achieve scaling;
    wire [7:0] din_buf1_wire = {din_buf1[3:0], 4'b0000};

    // we_buf2 is assigned in always block
    assign wraddr_buf2 = wraddr_buf2_r;

    // We write back to buf2 a total of 12 bits (RGB444) that we must "put together" from
    // the 8 bits that the Sobel filter produces for each pixel;
    wire [11:0] dout_buf2_wire = {dout_buf2_r[7:4], dout_buf2_r[7:4], dout_buf2_r[7:4]};
    assign dout_buf2 = dout_buf2_wire;

    // Sobel filter; we "drive" it with the "dummy" sync signals;
    // the idea is to have hsync go down for a clock cycle between rows;
    // that is an extra cycle during which we do not process a pixel;
    // it's just for edge_sobel_wrapper to work correctly;
    edge_sobel_wrapper #(
        .DATA_WIDTH(8)
    ) Inst_edge_sobel_wrapper (
        .clk(clk_div2),
        .fsync_in(vsync_dummy),
        .rsync_in(hsync_dummy),
        .pdata_in(din_buf1_wire),
        .fsync_out(vsync_delayed),
        .rsync_out(hsync_delayed),
        .pdata_out(dout_buf2_r)
    );

    // Divide clock by 2 and supply it as actual clock to edge_sobel_wrapper;
    // Note: we need it because we take 2 clk_i cycles for processing of a pixel;
    // edge_sobel_wrapper needs its own "clock" for each pixel, which is half
    // the frequency of clk_i;
    always @(posedge clk_i, posedge rst_i) begin
        if (rst_i == 1'b1) begin
            clk_div2 <= 1'b0;
        end else begin
            clk_div2 <= ~clk_div2;
        end
    end

    // Bring pixel by pixel and process it
    // Note: processing of each pixel takes two clock cycles of clk_i;
    always @(posedge clk_i) begin
        if (rst_i == 1'b1) begin
            state <= IDLE_ST;
            led_sobel_done <= 1'b0;
            rd_cntr <= 17'b0;
            wr_cntr <= 17'b0;
            we_buf2 <= 1'b0;
            rdaddr_buf1_r <= 17'b0;
            wraddr_buf2_r <= 17'b0;
            vsync_dummy <= 1'b0;
            hsync_dummy <= 1'b0;
            ColsCounter <= 9'b0;
        end else if (enable_sobel_filter == 1'b1 && state == IDLE_ST) begin
            state <= START_SOBEL_FILTER_ST;
            led_sobel_done <= 1'b0;
            rd_cntr <= 17'b0;
            wr_cntr <= 17'b0;
            we_buf2 <= 1'b1; // do not enable writing into buf2 until W+2 pixels have been processed;
            rdaddr_buf1_r <= 17'b0;
            wraddr_buf2_r <= 17'b0;
            vsync_dummy <= 1'b1;
            hsync_dummy <= 1'b0;
            ColsCounter <= 9'b0;
        end else begin
            case (state)
                // State START_SOBEL_FILTER_ST is visited once only for each frame/image
                START_SOBEL_FILTER_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    led_sobel_done <= 1'b0;
                    rd_cntr <= 17'b0;
                    wr_cntr <= 17'b0;
                    we_buf2 <= 1'b1; // stays like that during writes
                    rdaddr_buf1_r <= 17'b0;
                    wraddr_buf2_r <= 17'b0;
                    vsync_dummy <= 1'b1;
                    hsync_dummy <= 1'b0;
                    ColsCounter <= 9'b0;
                end

                // Each pixel goes thru these two states: GET_PIXEL_DATA_ST, SEND_PIXEL_DATA_ST
                GET_PIXEL_DATA_ST: begin
                    state <= SEND_PIXEL_DATA_ST;
                    rdaddr_buf1_r <= rdaddr_buf1_r + 1; // increment rd address for buf2
                    // increment wr address for buf2 only after W+2 pixels have been processed
                    if (rd_cntr > 17'd323) begin // 320; 323
                        wraddr_buf2_r <= wraddr_buf2_r + 1;
                        wr_cntr <= wr_cntr + 1;
                    end else begin
                        wraddr_buf2_r <= 17'b0;
                        wr_cntr <= 17'b0;
                    end
                end

                // Send back to buf2 the processed pixel
                SEND_PIXEL_DATA_ST: begin
                    // Tricky aspect: use wr_cntr here so that we continue to write into
                    // buf2 W+2 more pixels that we delayed at the beginning
                    if (wr_cntr < NUM_PIXELS) begin
                        rd_cntr <= rd_cntr + 1; // keep track of how many pixels we processed
                        if (ColsCounter < 9'd319) begin
                            ColsCounter <= ColsCounter + 1;
                            hsync_dummy <= 1'b1;
                            state <= GET_PIXEL_DATA_ST; // go to bring new pixel
                        end else begin
                            ColsCounter <= 9'b0;
                            hsync_dummy <= 1'b0;
                            state <= STALL_1_CYCLE_ST;
                        end
                    end else begin
                        state <= DONE_ST;
                    end
                end

                // At the end of each row of fetched pixels we "insert" a stall
                // during which we make hsync '0'; we need this trick for the
                // edge_sobel_wrapper entity to work correctly; 2 clk_i cycles
                // form one clkdiv2 cycle
                STALL_1_CYCLE_ST: begin
                    state <= STALL_2_CYCLE_ST;
                end

                STALL_2_CYCLE_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    hsync_dummy <= 1'b1;
                end

                // When arrived to this state, a whole frame was processed and we should
                // stay here and not repeat the process unless the whole thing is reset,
                // which places us again in IDLE_ST state
                DONE_ST: begin
                    state <= DONE_ST; // this way we read or write all pixels only once
                    led_sobel_done <= 1'b1; // notify user it's success; will be used for self reset too at top_level
                    we_buf2 <= 1'b0;
                end

                default: begin
                    state <= IDLE_ST;
                    led_sobel_done <= 1'b0;
                    we_buf2 <= 1'b0;
                end
            endcase
        end
    end

endmodule
