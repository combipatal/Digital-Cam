// Video Timing Control (VTC) module
// this module generates hsync and vsync signals for 640x480 resolution
//
// timings are parameterized but make sure pixel clock is correct!
//

module vtc 
    #(
    // total frame size
	 parameter RES_WIDTH     = 416, // 이전: 800
    parameter RES_HEIGHT    = 255, // 이전: 525

    // active area
    parameter ACTIVE_X      = 320, // 이전: 640
    parameter ACTIVE_Y      = 240, // 이전: 480

    // hsync pulse width, back porch, front porch
    parameter HSYNC_WIDTH   = 48,  // 이전: 96
    parameter HSYNC_BP      = 32,  // 이전: 48
    parameter HSYNC_FP      = 16,  // 이전: 16

    // vsync pulse width, back porch, front porch
    parameter VSYNC_WIDTH   = 2,   // 이전: 2
    parameter VSYNC_BP      = 10,  // 이전: 33
    parameter VSYNC_FP      = 3,   // 이전: 10

    parameter COUNTER_WIDTH = 10
    )
    (
    input wire i_clk,  // pixel clock
    input wire i_rstn, // synchronous active low reset

    // display timing
    output wire o_vsync,
    output wire o_hsync,
    output wire o_active,

    // counter passthrough
    output wire [COUNTER_WIDTH-1:0] o_counterX,
    output wire [COUNTER_WIDTH-1:0] o_counterY
    );

    

    // horizontal and vertical counters
    //localparam COUNTER_X_WIDTH = $clog2(RES_WIDTH);   
    //localparam COUNTER_Y_WIDTH = $clog2(RES_HEIGHT);
    reg [COUNTER_WIDTH-1:0] counterX;
    reg [COUNTER_WIDTH-1:0] counterY;


    initial begin
        counterX = 0;
        counterY = 0;
    end

//
// vsync and hsync counters
//
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            counterX <= 0;
        end
        else begin
            counterX <= (counterX == RES_WIDTH - 1) ? 0 : (counterX + 1); // 이전: 799
        end
    end

    always@(posedge i_clk) begin
        if(!i_rstn) begin
            counterY <= 0;
        end
        else begin
            if(counterX == RES_WIDTH - 1) begin // 이전: 799
                counterY <= (counterY == RES_HEIGHT - 1) ? 0 : (counterY + 1); // 이전: 524
            end
        end
    end

//
// output combinatorial logic
//
/*
    always@(posedge i_clk) begin
        if(!i_rstn) begin
            o_active <= 0;
            o_hsync  <= 0;
            o_vsync  <= 0;
        end
        else begin
            o_active <= (counterX < 640) && (counterY < 480);
            o_hsync  <= (counterX >= 656) && (counterX < 752);
            o_vsync  <= (counterY >= 490) && (counterY < 492);
        end
    end
*/
    assign o_hsync  = ((counterX >= ACTIVE_X + HSYNC_FP) && 
                       (counterX <  ACTIVE_X + HSYNC_FP + HSYNC_WIDTH));
 
    assign o_vsync  = ((counterY >= ACTIVE_Y + VSYNC_FP) &&
                      (counterY  <  ACTIVE_Y + VSYNC_FP + VSYNC_WIDTH));

    assign o_active = ((counterX >= 0) && (counterX < ACTIVE_X) &&
                       (counterY >= 0) && (counterY < ACTIVE_Y));

    assign o_counterX = counterX;
    assign o_counterY = counterY;

endmodule // vtc