// cam_top.v
//
// Encapsulates all camera-related modules into a single block.
//
module cam_top 
    #(parameter T_CFG_CLK = 8)
    (
    input  wire        i_cfg_clk,
    input  wire        i_rstn,
    input  wire        i_pclk_rstn,    // 캡처 로직용 리셋 (PCLK)

    // OV7670 I/O
    input  wire        i_cam_pclk,
    input  wire        i_cam_vsync,    // active-high, indicates start of frame
    input  wire        i_cam_href,     // active-high, indicates row data transmission
    input  wire [7:0]  i_cam_data,     // pixel data from camera

    // i2c bidirectional pins
    input  wire        i_scl,
    input  wire        i_sda,
    output wire        o_scl,
    output wire        o_sda,
        
    output        obuf_wr,
    output [11:0] obuf_wdata,
     
    // Configuration Control
    input  wire        i_cfg_init, // initialize cam registers to ROM
    output wire        o_cfg_done, // config done flag
    // debug
    output wire        o_cfg_busy, // I2C busy 신호 (추가)
    // Status Outputs
    output wire        o_sof,       // start of frame flag
	 output wire        o_vsync_posedge,
    output wire        o_vsync_negedge
    );

    wire cfg_busy_wire;

//---------------------------------------------------
//            Camera Configuration Module:
//---------------------------------------------------
    cfg_interface 
    #(.T_CLK(T_CFG_CLK) ) // 상위에서 받은 T_CFG_CLK 파라미터를 전달
    cfg_i (
    .i_clk   (i_cfg_clk     ), 
    .i_rstn  (i_rstn        ), // active-low sync reset 

    // controls
    .o_done  (o_cfg_done    ), // done flag
    .i_start (i_cfg_init    ), // initialize cam registers
    .o_busy  (cfg_busy_wire ), // busy 신호를 내부 wire에 연결
    // i2c pins
    .i_scl   (i_scl         ), 
    .i_sda   (i_sda         ),
    .o_scl   (o_scl         ),
    .o_sda   (o_sda         )
    );

    assign o_cfg_busy = cfg_busy_wire; // wire를 출력 포트로 연결

//---------------------------------------------------
//            Pixel Data Capture Module:
//---------------------------------------------------
    capture capture_i (
    .i_pclk     (i_cam_pclk       ), // camera pclk
    .i_rstn     (i_pclk_rstn      ), // active-low sync reset
    .i_cfg_done (o_cfg_done       ), // config module done flag
 
    // Camera Interface 
    .i_vsync    (i_cam_vsync      ), // vsync from camera
    .i_href     (i_cam_href       ), // href from camera
    .i_data     (i_cam_data       ), // 8-bit data
    
    // 24MHz to 125MHz FIFO Write interface
    .o_wr       (obuf_wr          ), // FIFO write enable
    .o_wdata    (obuf_wdata       ), // 12-bit RGB data

    .o_sof      (o_sof            ),
	 .vsync_posedge (o_vsync_posedge),
    .vsync_negedge (o_vsync_negedge)
    ); 

endmodule