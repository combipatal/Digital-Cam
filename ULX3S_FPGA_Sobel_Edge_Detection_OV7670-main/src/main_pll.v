//================================================================
// PLL for DE2-115 Board - Altera/Intel FPGA
// Input: 50MHz from CLOCK_50
// Outputs: 100MHz (SDRAM), 25MHz (VGA), 24MHz (Camera)
//================================================================
module main_pll (
    input wire inclk0,    // 50MHz input clock
    output wire c0,       // 100MHz for SDRAM
    output wire c1,       // 25MHz for VGA
    output wire c2,       // 24MHz for camera
    output wire locked    // PLL lock status
);

// PLL 매개변수 설정
// DE2-115에서는 Altera의 ALTPLL IP를 사용합니다.
// 다음 설정은 Quartus Prime에서 생성된 PLL IP와 호환됩니다.

// 내부 PLL 신호
wire [1:0] sub_wire0;
wire [4:0] sub_wire1;
wire sub_wire2;
wire sub_wire3;
wire sub_wire4;
wire sub_wire5;

// 출력 할당
assign c0 = sub_wire1[0];  // 100MHz
assign c1 = sub_wire1[1];  // 25MHz  
assign c2 = sub_wire1[2];  // 24MHz
assign locked = sub_wire2;

// DE2-115용 ALTPLL 인스턴스
// 실제 구현시에는 Quartus Prime의 MegaWizard를 사용하여
// IP를 생성하는 것을 권장합니다.
altpll altpll_component (
    .inclk ({{1{1'b0}}, inclk0}),
    .clk (sub_wire1),
    .locked (sub_wire2),
    .activeclock (),
    .areset (1'b0),
    .clkbad (),
    .clkena ({{5{1'b1}}}),
    .clkloss (),
    .clkswitch (1'b0),
    .configupdate (1'b0),
    .enable0 (),
    .enable1 (),
    .extclk (),
    .extclkena ({{4{1'b1}}}),
    .fbin (1'b1),
    .fbmimicbidir (),
    .fbout (),
    .fref (),
    .icdrclk (),
    .pfdena (1'b1),
    .phasecounterselect ({{4{1'b1}}}),
    .phasedone (),
    .phasestep (1'b1),
    .phaseupdown (1'b1),
    .pllena (1'b1),
    .scanaclr (1'b0),
    .scanclk (1'b0),
    .scanclkena (1'b1),
    .scandata (1'b0),
    .scandataout (),
    .scandone (),
    .scanread (1'b0),
    .scanwrite (1'b0),
    .sclkout0 (),
    .sclkout1 (),
    .vcooverrange (),
    .vcounderrange ()
);

defparam
    altpll_component.bandwidth_type = "AUTO",
    altpll_component.clk0_divide_by = 1,
    altpll_component.clk0_duty_cycle = 50,
    altpll_component.clk0_multiply_by = 2,
    altpll_component.clk0_phase_shift = "0",
    altpll_component.clk1_divide_by = 2,
    altpll_component.clk1_duty_cycle = 50,
    altpll_component.clk1_multiply_by = 1,
    altpll_component.clk1_phase_shift = "0",
    altpll_component.clk2_divide_by = 25,
    altpll_component.clk2_duty_cycle = 50,
    altpll_component.clk2_multiply_by = 12,
    altpll_component.clk2_phase_shift = "0",
    altpll_component.compensate_clock = "CLK0",
    altpll_component.inclk0_input_frequency = 20000, // 50MHz = 20ns period
    altpll_component.intended_device_family = "Cyclone IV E",
    altpll_component.lpm_hint = "CBX_MODULE_PREFIX=main_pll",
    altpll_component.lpm_type = "altpll",
    altpll_component.operation_mode = "NORMAL",
    altpll_component.pll_type = "AUTO",
    altpll_component.port_activeclock = "PORT_UNUSED",
    altpll_component.port_areset = "PORT_UNUSED",
    altpll_component.port_clkbad0 = "PORT_UNUSED",
    altpll_component.port_clkbad1 = "PORT_UNUSED",
    altpll_component.port_clkloss = "PORT_UNUSED",
    altpll_component.port_clkswitch = "PORT_UNUSED",
    altpll_component.port_configupdate = "PORT_UNUSED",
    altpll_component.port_fbin = "PORT_UNUSED",
    altpll_component.port_inclk0 = "PORT_USED",
    altpll_component.port_inclk1 = "PORT_UNUSED",
    altpll_component.port_locked = "PORT_USED",
    altpll_component.port_pfdena = "PORT_UNUSED",
    altpll_component.port_phasecounterselect = "PORT_UNUSED",
    altpll_component.port_phasedone = "PORT_UNUSED",
    altpll_component.port_phasestep = "PORT_UNUSED",
    altpll_component.port_phaseupdown = "PORT_UNUSED",
    altpll_component.port_pllena = "PORT_UNUSED",
    altpll_component.port_scanaclr = "PORT_UNUSED",
    altpll_component.port_scanclk = "PORT_UNUSED",
    altpll_component.port_scanclkena = "PORT_UNUSED",
    altpll_component.port_scandata = "PORT_UNUSED",
    altpll_component.port_scandataout = "PORT_UNUSED",
    altpll_component.port_scandone = "PORT_UNUSED",
    altpll_component.port_scanread = "PORT_UNUSED",
    altpll_component.port_scanwrite = "PORT_UNUSED",
    altpll_component.width_clock = 5;

endmodule

// 대안: 간단한 클럭 분주기 버전 (PLL IP가 없는 경우 사용)
/*
module main_pll_simple (
    input wire inclk0,    // 50MHz input clock
    output reg c0,        // 100MHz for SDRAM (실제로는 50MHz 사용)
    output reg c1,        // 25MHz for VGA
    output reg c2,        // 24MHz for camera (실제로는 약 25MHz)
    output wire locked    // Always locked
);

reg [1:0] div_counter;
reg clk_25;

assign locked = 1'b1;  // 항상 잠금 상태
assign c0 = inclk0;    // 50MHz (SDRAM용으로는 충분)

// 25MHz 클럭 생성 (50MHz를 2로 분주)
always @(posedge inclk0) begin
    div_counter <= div_counter + 1;
end

assign c1 = div_counter[0];  // 25MHz
assign c2 = div_counter[0];  // 25MHz (카메라용)

endmodule
*/