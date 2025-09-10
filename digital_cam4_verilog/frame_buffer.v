// 320x240 (총 76800) 픽셀 프레임 버퍼
// 각 픽셀은 12비트입니다.
// 64K(2^16) 용량을 갖는 RAM 블록 두 개를 사용하여 구현하며,
// 주소의 최상위 비트(MSB)로 두 RAM 블록을 선택합니다.

module frame_buffer (
    input [11:0] data,
    input [16:0] rdaddress,
    input rdclock,
    input [16:0] wraddress,
    input wrclock,
    input wren,
    output [11:0] q
);

    // 내부 신호
    wire [11:0] q_top, q_bottom;     // 각 RAM 블록의 읽기 출력
    wire wren_top, wren_bottom;     // 각 RAM 블록의 쓰기 인에이블

    // 쓰기 인에이블 신호 분배
    // 주소의 17번째 비트(wraddress[16])에 따라 하나의 RAM 블록만 활성화
    assign wren_top    = (wraddress[16] == 1'b0) ? wren : 1'b0;
    assign wren_bottom = (wraddress[16] == 1'b1) ? wren : 1'b0;

    // 읽기 데이터 멀티플렉서
    // 주소의 17번째 비트(rdaddress[16])에 따라 적절한 RAM 출력을 선택
    assign q = (rdaddress[16] == 1'b0) ? q_top : q_bottom;

    // 상위 주소 공간(0 ~ 65535)을 위한 RAM 블록 인스턴스
    my_frame_buffer_15to0 Inst_buffer_top (
        .data(data),
        .rdaddress(rdaddress[15:0]),
        .rdclock(rdclock),
        .wraddress(wraddress[15:0]),
        .wrclock(wrclock),
        .wren(wren_top),
        .q(q_top)
    );

    // 하위 주소 공간(65536 ~ 131071)을 위한 RAM 블록 인스턴스
    my_frame_buffer_15to0 Inst_buffer_bottom (
        .data(data),
        .rdaddress(rdaddress[15:0]),
        .rdclock(rdclock),
        .wraddress(wraddress[15:0]),
        .wrclock(wrclock),
        .wren(wren_bottom),
        .q(q_bottom)
    );

endmodule
