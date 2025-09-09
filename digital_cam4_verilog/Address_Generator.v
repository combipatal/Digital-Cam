// VHDL 소스 파일: address_Generator.vhd
// 640x480 화면 중앙에 320x240 이미지를 표시하도록 주소 생성 로직을 수정했습니다.

module Address_Generator (
    input wire          rst_i,
    input wire          CLK25,
    // --- 수정/추가된 입력 포트 ---
    input wire  [9:0]   Hcnt,       // VGA의 수평 카운터
    input wire  [9:0]   Vcnt,       // VGA의 수직 카운터
    output wire [16:0]  address,    // 생성된 프레임 버퍼 주소
    output wire         enable_out  // 실제 이미지 데이터가 유효한 영역 신호
);

    // 320x240 이미지 정보
    localparam IMAGE_WIDTH = 320;
    localparam IMAGE_HEIGHT = 240;

    // 640x480 화면 중앙 좌표 계산
    localparam H_START = (640 - IMAGE_WIDTH) / 2; // (640-320)/2 = 160
    localparam H_END   = H_START + IMAGE_WIDTH;   // 160+320 = 480
    localparam V_START = (480 - IMAGE_HEIGHT) / 2; // (480-240)/2 = 120
    localparam V_END   = V_START + IMAGE_HEIGHT;  // 120+240 = 360

    // 내부 레지스터
    reg [16:0] addr_reg;
    reg enable_reg;

    always @(posedge CLK25) begin
        if (rst_i) begin
            addr_reg <= 0;
            enable_reg <= 1'b0;
        end else begin
            // 현재 VGA 스캔 위치가 320x240 이미지 영역 내에 있는지 확인
            if ((Hcnt >= H_START) && (Hcnt < H_END) && (Vcnt >= V_START) && (Vcnt < V_END)) begin
                enable_reg <= 1'b1;
                // 이미지 영역 내에서의 상대 좌표 계산
                // Y 좌표 * 이미지 가로 길이 + X 좌표
                addr_reg <= (Vcnt - V_START) * IMAGE_WIDTH + (Hcnt - H_START);
            end else begin
                // 이미지 영역 밖은 비활성화
                enable_reg <= 1'b0;
                addr_reg <= 0; // 주소는 0으로 유지 (Don't care)
            end
        end
    end
    
    assign address = addr_reg;
    assign enable_out = enable_reg;

endmodule

