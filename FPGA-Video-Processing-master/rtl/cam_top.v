// cam_top.v (수정 완료)
module cam_top 
    #(parameter T_CFG_CLK = 8)
    (
    input  wire        i_cfg_clk,
    input  wire        i_rstn,

    // OV7670 I/O
    input  wire        i_cam_pclk,
    input  wire        i_cam_vsync,    // active-high, indicates start of frame
    input  wire        i_cam_hsync,    // [수정] href에서 변경
    input  wire [7:0]  i_cam_data,     // pixel data from camera

    // i2c bidirectional pins
    input  wire        i_scl,
    input  wire        i_sda,
    output wire        o_scl,
    output wire        o_sda,

    // Output Buffer FIFO
    input  wire        i_obuf_rclk,
    input  wire        i_obuf_rstn,
    input  wire        i_obuf_rd,
    output wire [11:0] o_obuf_data,
    output wire        o_obuf_empty,
    output wire        o_obuf_almostempty,
    output wire [3:0]  o_obuf_fill,

    // Configuration Control
    input  wire        i_cfg_init, 
    output wire        o_cfg_done, 

    // Status Outputs
    output wire        o_sof       
    );

    wire        obuf_wr;
    wire [11:0] obuf_wdata;
         
    cfg_interface 
    #(.T_CLK(8) )
    cfg_i (
    .i_clk   (i_cfg_clk     ), 
    .i_rstn  (i_rstn        ), 
    .o_done  (o_cfg_done    ), 
    .i_start (i_cfg_init    ), 
    .i_scl   (i_scl         ), 
    .i_sda   (i_sda         ),
    .o_scl   (o_scl         ),
    .o_sda   (o_sda         )
    );

    cam_capture capture_i (
        .i_pclk     (i_cam_pclk       ), 
        .i_rstn     (i_rstn           ), 
        .i_cfg_done (o_cfg_done       ), 
    
        // Camera Interface 
        .i_vsync    (i_cam_vsync      ), 
        .i_hsync    (i_cam_hsync      ), // [수정] href 대신 hsync 연결
        .i_data     (i_cam_data       ), 
        
        // 24MHz to 125MHz FIFO Write interface
        .o_wr       (obuf_wr          ), 
        .o_wdata    (obuf_wdata       ), 

        .o_sof      (o_sof            )
    );

    fifo_async frontFIFO_i (
    .wrclk      (i_cam_pclk),    
    .wrreq      (obuf_wr),       
    .data       (obuf_wdata),    
    .rdclk      (i_obuf_rclk),   
    .rdreq      (i_obuf_rd),     
    .q          (o_obuf_data),   
    .rdempty    (o_obuf_empty),  
    .wrfull     (),              
    .aclr       (!i_rstn || !i_obuf_rstn)
    );
endmodule