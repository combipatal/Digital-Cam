// Read buffer 1 content and apply black-and-white filter;
// Write into buffer 2 the B&W image;

module do_black_white(
    // controls
    input rst_i,
    input clk_i, // 25 MHz
    input enable_filter,
    output reg led_done,
    // connections from frame buffer 1 from where we
    // need to read image data (e.g., current frame) and to which
    // we must apply B&W filter; we need here to generate "read" addresses;
    output [16:0] rdaddr_buf1,
    input [11:0] din_buf1,
    // connections to frame buffer 2 for which we need to
    // generate "write" addresses and pass pixel data after B&W processing;
    output [16:0] wraddr_buf1,
    output [11:0] dout_buf1,
    output reg we_buf1
);

    // Component instantiation for binary divider
    wire [7:0] quotient;
    wire [7:0] remainder;

    // State machine states
    localparam [2:0]
        START_BLACKWHITE_ST = 3'b000,
        GET_PIXEL_DATA_ST = 3'b001,
        WAIT_ACK_DIVISION_ST = 3'b010,
        SEND_PIXEL_DATA_ST = 3'b011,
        DONE_ST = 3'b100,
        IDLE_ST = 3'b101;

    // Used for "average method" that does (R + G + B) / 3
    localparam [7:0] CONSTANT_THREE = 8'b00000011;

    // We need to read 320x240 = 76800 locations;
    localparam [16:0] NUM_PIXELS = 17'd76799;

    // Signal that B&W filter is done
    // (led_done is used directly)

    // Coming from buffer 1, regular pixel data
    reg [16:0] rdaddr_buf1_r = 17'b0;

    // Going to buffer 2, B&W pixels data
    reg [16:0] wraddr_buf1_r = 17'b0;

    // Counter of pixels
    reg [16:0] rw_cntr = 17'b0;

    // State of the FSM that implements the read or write steps
    reg [2:0] state = IDLE_ST;

    wire [7:0] red, green, blue;
    wire [7:0] red_grey, green_grey, blue_grey;
    wire [7:0] r_plus_g_plus_b;

    // Assign outputs
    // led_done is assigned in always block
    assign rdaddr_buf1 = rdaddr_buf1_r;
    assign wraddr_buf1 = wraddr_buf1_r;

    // Black and white processing of pixel data
    // Actually, here, we convert a color image to grayscale
    // The "average method" simply averages the values: (R + G + B) / 3
    assign red = {4'b0000, din_buf1[11:8]};
    assign green = {4'b0000, din_buf1[7:4]};
    assign blue = {4'b0000, din_buf1[3:0]};
    assign r_plus_g_plus_b = red + green + blue;

    // Instantiate binary divider
    binary_divider_ver1 #(.size(8)) Inst_binary_divider(
        .A(r_plus_g_plus_b),
        .B(CONSTANT_THREE),
        .Q(red_grey), // quotient of (red + green + blue)/3
        .R(remainder)
    );

    assign green_grey = red_grey;
    assign blue_grey = red_grey;
    assign dout_buf1 = {red_grey[3:0], green_grey[3:0], blue_grey[3:0]};

    // Bring pixel by pixel and process it
    always @(posedge clk_i) begin
        if (rst_i == 1'b1) begin
            state <= IDLE_ST;
            led_done <= 1'b0;
            we_buf1 <= 1'b0;
        end else if (enable_filter == 1'b1 && state == IDLE_ST) begin
            state <= START_BLACKWHITE_ST;
            rw_cntr <= 17'b0;
            we_buf1 <= 1'b1;
            led_done <= 1'b0;
            rdaddr_buf1_r <= 17'b0;
            wraddr_buf1_r <= 17'b0;
        end else begin
            case (state)
                // State START_BLACKWHITE_ST is visited once only for each frame/image
                START_BLACKWHITE_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    rw_cntr <= 17'b0;
                    we_buf1 <= 1'b1; // stays like that during writes
                    rdaddr_buf1_r <= 17'b0;
                    wraddr_buf1_r <= 17'b0;
                end

                // Each pixel goes thru these two states: GET_PIXEL_DATA_ST, SEND_PIXEL_DATA_ST
                // Get the new pixel data for B&W processing
                GET_PIXEL_DATA_ST: begin
                    state <= SEND_PIXEL_DATA_ST;
                    rdaddr_buf1_r <= rdaddr_buf1_r + 1; // increment rd address for buf2
                    wraddr_buf1_r <= wraddr_buf1_r + 1; // increment wr address for buf2
                end

                // Note: next state is not currently used; we would use it if we used a
                // divider that is not combinational, and would take multiple clock cycles
                WAIT_ACK_DIVISION_ST: begin
                    // If the logic responsible with converting the pixel data into
                    // black and white is done move on; else "stall" in this state
                    state <= SEND_PIXEL_DATA_ST;
                    wraddr_buf1_r <= wraddr_buf1_r + 1; // increment wr address for buf2
                end

                // Send back to buffer 2 the B&W pixel
                SEND_PIXEL_DATA_ST: begin
                    if (rw_cntr < NUM_PIXELS) begin
                        state <= GET_PIXEL_DATA_ST; // go to bring new pixel
                        rw_cntr <= rw_cntr + 1; // keep track of how many pixels we processed
                    end else begin
                        state <= DONE_ST;
                    end
                end

                // When arrived to this state, a whole frame was processed and we should
                // stay here and not repeat the process unless the whole thing is reset,
                // which places us again in IDLE_ST state
                DONE_ST: begin
                    state <= DONE_ST; // this way we read or write all pixels only once
                    led_done <= 1'b1; // notify user it's success; will be used for self reset too at top_level
                    we_buf1 <= 1'b0;
                end

                default: begin
                    state <= IDLE_ST;
                    led_done <= 1'b0;
                    we_buf1 <= 1'b0;
                end
            endcase
        end
    end

endmodule
