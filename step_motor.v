module Step_Motor_Controller (
    input clk,              // 50MHz
    input rst,
    input engine_on,        // 시동 여부
    input key_left,         // 4번 키 (좌회전)
    input key_right,        // 5번 키 (우회전)
    input key_center,       // 2번 키 (원위치 복귀)
    output reg [3:0] step_out // 모터 출력
);

    // --- 1. 속도 및 거리 설정 ---
    
    // [파워 핸들 ON] 시동 켜졌을 때 속도 (기존 속도)
    parameter SPEED_FAST = 900_000; 
    
    // [파워 핸들 OFF] 시동 꺼졌을 때 속도 (4배 느리게 -> 무거운 느낌)
    parameter SPEED_SLOW = 1_600_000; 

    // 한 바퀴 반 제한 (사용자 설정값 유지)
    parameter LIMIT_POS = 75; 

    reg [21:0] cnt; // 카운터 비트수 넉넉하게 증가 (20->21)
    reg tick;
    reg [2:0] step_idx; 
    reg signed [31:0] current_pos; 

    // 현재 상태에 따른 속도 결정 (Mux)
    wire [21:0] current_speed_limit;
    assign current_speed_limit = (engine_on) ? SPEED_FAST : SPEED_SLOW;

    // --- 2. 속도(Tick) 생성 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt <= 0; tick <= 0;
        end else begin
            // engine_on 여부에 따라 목표 카운트(current_speed_limit)가 달라짐
            if (cnt >= current_speed_limit) begin
                cnt <= 0; tick <= 1;
            end else begin
                cnt <= cnt + 1; tick <= 0;
            end
        end
    end

    // --- 3. 모터 제어 로직 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            step_idx <= 0;
            step_out <= 4'b0000;
            current_pos <= 0; 
        end else if (tick) begin 
            // [수정됨] && engine_on 조건 제거! 
            // 이제 시동이 꺼져도 tick(느린 속도)만 발생하면 움직입니다.

            // (1) 좌회전 (4번 키)
            if (key_left && !key_right) begin
                if (current_pos < LIMIT_POS) begin
                    step_idx <= step_idx + 1;
                    current_pos <= current_pos + 1;
                end
            end 
            
            // (2) 우회전 (5번 키)
            else if (key_right && !key_left) begin
                if (current_pos > -LIMIT_POS) begin
                    step_idx <= step_idx - 1;
                    current_pos <= current_pos - 1;
                end
            end
            
            // (3) 원위치 복귀 (2번 키)
            else if (key_center) begin
                if (current_pos > 0) begin       
                    step_idx <= step_idx - 1;    
                    current_pos <= current_pos - 1;
                end else if (current_pos < 0) begin 
                    step_idx <= step_idx + 1;   
                    current_pos <= current_pos + 1;
                end
            end
            
            // 스텝 출력
            case (step_idx)
                3'd0: step_out <= 4'b1000;
                3'd1: step_out <= 4'b1100;
                3'd2: step_out <= 4'b0100;
                3'd3: step_out <= 4'b0110;
                3'd4: step_out <= 4'b0010;
                3'd5: step_out <= 4'b0011;
                3'd6: step_out <= 4'b0001;
                3'd7: step_out <= 4'b1001;
            endcase
        end 
        // [수정됨] else if (!engine_on) 삭제. 
        // 시동 꺼져도 모터에 전원이 들어가야 핸들을 돌릴 수 있음 (토크 유지 or 회전)
    end

endmodule