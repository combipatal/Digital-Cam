// VHDL 소스 파일: frame_buffer.vhd
// 320x240 픽셀 프레임(총 76800 픽셀)을 저장하기 위한 버퍼입니다.
// 각 픽셀 데이터는 12비트입니다.
// 주소는 17비트(2^17 = 131072)로 표현됩니다.
// 65536 (2^16) 워드 크기의 RAM 블록 두 개를 쌓아 구현합니다.

module frame_buffer (
    input wire [11:0]   data,
    input wire [16:0]   rdaddress,
    input wire          rdclock,
    input wire [16:0]   wraddress,
    input wire          wrclock,
    input wire          wren,
    output reg [11:0]   q
);

    // 내부 신호
    wire [11:0] q_top;
    wire [11:0] q_bottom;
    wire        wren_top;
    wire        wren_bottom;
    
    // 주소의 최상위 비트(16)를 사용하여 두 개의 RAM 블록 중 하나를 활성화합니다.
    assign wren_top    = (wraddress[16] == 1'b0) ? wren : 1'b0;
    assign wren_bottom = (wraddress[16] == 1'b1) ? wren : 1'b0;

    // 두 개의 RAM 블록(my_frame_buffer_15to0) 인스턴스화
    my_frame_buffer_15to0 Inst_buffer_top (
        .data       (data),
        .rdaddress  (rdaddress[15:0]),
        .rdclock    (rdclock),
        .wraddress  (wraddress[15:0]),
        .wrclock    (wrclock),
        .wren       (wren_top),
        .q          (q_top)
    );

    my_frame_buffer_15to0 Inst_buffer_bottom (
        .data       (data),
        .rdaddress  (rdaddress[15:0]),
        .rdclock    (rdclock),
        .wraddress  (wraddress[15:0]),
        .wrclock    (wrclock),
        .wren       (wren_bottom),
        .q          (q_bottom)
    );

    // 읽기 주소의 최상위 비트에 따라 적절한 RAM 블록의 출력을 선택합니다.
    always @(*) begin
        case (rdaddress[16])
            1'b0:    q = q_top;
            1'b1:    q = q_bottom;
            default: q = 12'h000;
        endcase
    end

endmodule
