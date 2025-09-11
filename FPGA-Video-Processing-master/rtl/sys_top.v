// sys_top.v (수정 완료)
`default_nettype none

module sys_top 
    (
    input  wire       clk_50MHz,
    input  wire       i_rst,       // active-high board button

    // camera interface
    output wire       o_cam_xclk,  // 24MHz clock to camera from DCM
    output wire       o_cam_rstn,  // camera active low reset
    output wire       o_cam_pwdn,  // camera active high power down 

    input  wire       i_cam_pclk,  // camera generated pixel clock
    input  wire       i_cam_vsync, // camera vsync
    input  wire       i_cam_hsync, // [수정] i_cam_href에서 변경
    input  wire [7:0] i_cam_data,  // camera 8-bit data in

    // i2c interface
    inout  wire       SCL,         // bidirectional SCL
    inout  wire       SDA,         // bidirectional SDA

    // VGA
    output wire [7:0] o_VGA_R,
    output wire [7:0] o_VGA_G,
	 output wire [7:0] o_VGA_B,
	 output wire	 	 o_VGA_HS,
	 output wire 		 o_VGA_VS,
	 
    // controls
    input  wire       btn_mode,
    input  wire       btn_decSobel,
    input  wire       btn_incSobel,

    input  wire       sw_gaussian,
    input  wire       sw_sobel,
    input  wire       sw_freeze,

    // status
    output wire       led_mode,
    output wire       led_gaussian,
    output wire       led_sobel,
    output wire       led_threshold
    );
// =============================================================
//              Parameters, Registers, and Wires
// =============================================================
// PLL
    wire        clk_25MHz;
    wire        i_sysclk;
// Debounce
    wire        db_rstn;
// System Control
    wire        cfg_start;
    wire        sys_mode;
    wire        gaussian_enable;
    wire        sobel_enable;
    wire        pipe_flush;
    wire [25:0] sobel_threshold;
    wire        thresholdBounds;
// Camera Block
    wire        i_scl, i_sda;
    wire        o_scl, o_sda;
    wire        sof;
    wire        cam_obuf_rd;
    wire [11:0] cam_obuf_rdata;
    wire        cam_obuf_almostempty;
    wire        cfg_done;
// Greyscale Block
    wire        pp_obuf_rd;
    wire [11:0] pp_obuf_rdata;
    wire        pp_obuf_almostempty;
    wire [10:0] pp_obuf_fill;
// Gaussian Block
    wire        gssn_obuf_rd;
    wire [11:0] gssn_obuf_rdata;
    wire        gssn_obuf_almostempty;

// Sobel Block
    wire        sobel_obuf_rd;
    wire [11:0] sobel_obuf_rdata;
    wire        sobel_obuf_almostempty;
// Display Interface
    wire [18:0] framebuf_raddr;
    wire [11:0] framebuf_rdata;
// =============================================================
//                    Implementation:
// =============================================================
    assign o_cam_rstn = 1'b1;
    assign o_cam_pwdn = 1'b0;  

    assign led_mode      = sys_mode;
    assign led_gaussian  = gaussian_enable;
    assign led_sobel     = sobel_enable;
    assign led_threshold = thresholdBounds;
// **** Debounce Reset button ****
    debounce 
    #(.DB_COUNT(1))
    db_inst (
    .i_clk   (i_cam_pclk ),
    .i_input (~i_rst     ),
    .o_db    (db_rstn    )
    );
// **** Async Reset Synchronizers ****
    reg sync_rstn_PS, q_rstn_PS;
    always@(posedge i_sysclk or negedge db_rstn) begin
        if(!db_rstn) {sync_rstn_PS, q_rstn_PS} <= 2'b0;
        else         {sync_rstn_PS, q_rstn_PS} <= {q_rstn_PS, 1'b1};
    end

    reg sync_rstn_25, q_rstn_25;
    always@(posedge clk_25MHz or negedge db_rstn) begin
        if(!db_rstn) {sync_rstn_25, q_rstn_25} <= 2'b0;
        else         {sync_rstn_25, q_rstn_25} <= {q_rstn_25, 1'b1};
    end

// =============================================================
//                    Submodule Instantiation:
// =============================================================
    PLL_clk 
    pll_init (
        .inclk0     (clk_50MHz      ),
        .c0         (o_cam_xclk    ),
        .c1         (clk_25MHz     )
    );
    PLL_125MHz
    pll_init_125 (
        .inclk0     (clk_50MHz   ),
        .c0         (i_sysclk    )
    );
    sys_control 
    ctrl_i (
        .i_sysclk          (i_sysclk        ),
        .i_rstn            (sync_rstn_PS    ),
        .i_sof             (sof             ),
        .i_btn_mode        (btn_mode        ),
        .i_sw_gaussian     (sw_gaussian     ),
        .i_sw_sobel        (sw_sobel        ),
        .i_btn_incSobel    (btn_incSobel    ),
        .i_btn_decSobel    (btn_decSobel    ),
        .o_cfg_start       (cfg_start       ),
        .o_gaussian_enable (gaussian_enable ),
        .o_sobel_enable    (sobel_enable    ),
        .o_mode            (sys_mode        ),
        .o_pipe_flush      (pipe_flush      ),
        .o_sobel_threshold (sobel_threshold ),
        .o_thresholdBounds (thresholdBounds )              
    );

    assign SCL = (o_scl) ? 1'bz : 1'b0;
    assign SDA = (o_sda) ? 1'bz : 1'b0;
    assign i_scl = SCL;
    assign i_sda = SDA;

    cam_top 
    #(.T_CFG_CLK(8))
    cam_i (
    .i_cfg_clk          (i_sysclk        ),
    .i_rstn             (sync_rstn_PS    ),
    .o_sof              (sof             ),
    
    // OV7670 external inputs    
    .i_cam_pclk         (i_cam_pclk      ),
    .i_cam_vsync        (i_cam_vsync     ),
    .i_cam_hsync        (i_cam_hsync     ), // [수정] href 대신 hsync 연결
    .i_cam_data         (i_cam_data      ),

    // i2c bidirectional pins
    .i_scl              (i_scl           ),
    .i_sda              (i_sda           ),
    .o_scl              (o_scl           ),
    .o_sda              (o_sda           ),

    // Controls
    .i_cfg_init         (cfg_start       ),
    .o_cfg_done         (cfg_done        ),

    // output buffer read interface
    .i_obuf_rclk        (i_sysclk        ),
    .i_obuf_rstn        (sync_rstn_PS    ),
    .i_obuf_rd          (cam_obuf_rd     ),
    .o_obuf_data        (cam_obuf_rdata  ),
    .o_obuf_empty       (),  
    .o_obuf_almostempty (cam_obuf_almostempty ),  
    .o_obuf_fill        ()

    );

    pp_preprocess pp_i (
    .i_clk         (i_sysclk             ),
    .i_rstn        (sync_rstn_PS         ),
    .i_flush       (pipe_flush||sw_freeze),
    .i_mode        (sys_mode             ),
    .o_rd          (cam_obuf_rd          ),
    .i_data        (cam_obuf_rdata       ),
    .i_almostempty (cam_obuf_almostempty ),
    .i_rd          (pp_obuf_rd           ),
    .o_data        (pp_obuf_rdata        ),
    .o_fill        (), 
    .o_almostempty (pp_obuf_almostempty  )
    );

    ps_gaussian_top gaussian_i (
    .i_clk              (i_sysclk),
    .i_rstn             (sync_rstn_PS),
    .i_enable           (gaussian_enable),
    .i_flush            (pipe_flush||sw_freeze),
    .i_data             (pp_obuf_rdata),
    .i_almostempty      (pp_obuf_almostempty),
    .o_rd               (pp_obuf_rd),
    .i_obuf_rd          (gssn_obuf_rd),
    .o_obuf_data        (gssn_obuf_rdata),
    .o_obuf_fill        (),
    .o_obuf_full        (),
    .o_obuf_almostfull  (),
    .o_obuf_empty       (),
    .o_obuf_almostempty (gssn_obuf_almostempty)
    );

    ps_sobel_top sobel_i (
    .i_clk              (i_sysclk),
    .i_rstn             (sync_rstn_PS),
    .i_enable           (sobel_enable),
    .i_flush            (pipe_flush||sw_freeze),
    .i_threshold        (sobel_threshold),
    .i_data             (gssn_obuf_rdata),
    .i_almostempty      (gssn_obuf_almostempty),
    .o_rd               (gssn_obuf_rd),
    .i_obuf_rd          (sobel_obuf_rd),
    .o_obuf_data        (sobel_obuf_rdata),
    .o_obuf_fill        (),
    .o_obuf_full        (),
    .o_obuf_almostfull  (),
    .o_obuf_empty       (),
    .o_obuf_almostempty (sobel_obuf_almostempty)
    );

    mem_interface 
    #(.DATA_WIDTH (12),
      .BRAM_DEPTH (76800) 
     )
    mem_i(
    .i_clk         (i_sysclk               ),
    .i_rstn        (sync_rstn_PS           ),
    .i_flush       (pipe_flush||sw_freeze  ),
    .o_rd          (sobel_obuf_rd          ),
    .i_rdata       (sobel_obuf_rdata       ),
    .i_almostempty (sobel_obuf_almostempty ),
    .i_rclk        (clk_25MHz              ),
    .i_raddr       (framebuf_raddr         ),
    .o_rdata       (framebuf_rdata         )
    );

    display_interface 
    display_i(
    .i_p_clk       (clk_25MHz       ),
    .i_rstn        (sync_rstn_25    ), 
    .i_mode        (sys_mode        ),
    .o_raddr       (framebuf_raddr  ),
    .i_rdata       (framebuf_rdata  ),
    .o_VGA_R       (o_VGA_R         ),
    .o_VGA_G       (o_VGA_G         ),
    .o_VGA_B       (o_VGA_B         ),
    .o_VGA_HS      (o_VGA_HS        ),
    .o_VGA_VS      (o_VGA_VS        )
    );

endmodule