module Warning_Light_Logic (
    input clk,
    input rst,
    input tick_1sec,         // 시간 카운트용
    
    input sw_hazard,         // DIP 스위치 입력 (SW3)
    input ess_trigger,       // Vehicle_Logic에서 온 급제동 신호
    input is_accel_pressed,  // 악셀을 밟았는지 여부 (재출발 감지)
    
    output reg blink_out     // 최종 비상등 깜빡임 신호
);

    // --- 1. ESS 유지 타이머 로직 ---
    reg [2:0] ess_timer;     // 3초 카운터
    reg ess_active;          // ESS 활성화 상태 플래그

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ess_active <= 0;
            ess_timer <= 0;
        end else begin
            // [조건 A] 급제동 신호가 들어오면 ESS 모드 시작
            if (ess_trigger) begin
                ess_active <= 1;
                ess_timer <= 3; // 3초 유지 설정
            end
            
            // [조건 B] ESS 끄는 조건
            else if (ess_active) begin
                // 1. 악셀을 밟으면 즉시 끔 (재출발)
                if (is_accel_pressed) begin
                    ess_active <= 0;
                    ess_timer <= 0;
                end
                // 2. 타이머가 0이 되면 끔
                else if (ess_timer == 0) begin
                    ess_active <= 0;
                end
                // 3. 타이머 감소 (1초마다)
                else if (tick_1sec) begin
                    ess_timer <= ess_timer - 1;
                end
            end
        end
    end

    // --- 2. 깜빡임 주기 생성 (0.5초 간격) ---
    reg [24:0] blink_cnt;
    wire blink_pulse;
    // 50MHz 클럭 기준 약 0.5초 (25,000,000)
    always @(posedge clk or posedge rst) begin
        if (rst) blink_cnt <= 0;
        else if (blink_cnt >= 25_000_000) blink_cnt <= 0;
        else blink_cnt <= blink_cnt + 1;
    end
    assign blink_pulse = (blink_cnt < 12_500_000); // 0.5초 ON, 0.5초 OFF

    // --- 3. 최종 출력 결정 (OR 로직) ---
    always @(*) begin
        // DIP 스위치(SW3)가 켜져 있거나(OR) ESS가 활성화 상태면 깜빡임
        if (sw_hazard || ess_active) begin
            blink_out = blink_pulse;
        end else begin
            blink_out = 0; // 둘 다 아니면 꺼짐
        end
    end

endmodule