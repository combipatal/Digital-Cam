

module vga_controller_1 (





);



//수평 카운터
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
        h_count <= 10'd0;

    end else if (h_count == H_TOTAL - 1)begin   //  한 스캔 라인이 끝 
        h_count <= 10'd0;                       // 다시 처음으로 돌아가기

    end else begin
        h_count <= h_count + 10'd1;       // 1 증가

    end
    
end

//수직 카운터
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
        v_count <= 10'd0;

    end else if (h_count == H_TOTAL - 1) begin  // 수평 한 줄이 끝나고 
        if (v_count == V_TOTAL - 1)begin   // 한 프레임이 끝 
            v_count <= 10'd0;

        end else begin                      //수평 한 줄만 끝이 난다면 
            v_count <= v_count + 10'd1;     // 수직 카운터 1 증가

        end

    end
end

//h_sync 신호 생성
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
        h_sync <= 1'b1;     // 기본은 high
    end else if (h_count > (H_DISPLAY  + H_FRONT) && 
                h_count < (H_DISPLAY  + H_FRONT + H_SYNC)) begin
        h_sync <= 1'b0;     // 지정된 구간에선 low
    end else begin
        h_sync <= 1'b1;     // 기본은 high
    end
end

endmodule
