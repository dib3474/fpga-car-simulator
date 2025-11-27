module Sound_Unit (
    input clk, input rst,
    input is_horn, input turn_signal_pulse, // 깜빡이 펄스 입력
    output reg piezo_out
);
    reg prev_sig;
    reg [19:0] click_timer;
    reg click_en;
    reg [15:0] tone_cnt;
    reg wave;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_sig<=0; click_timer<=0; click_en<=0;
        end else begin
            prev_sig <= turn_signal_pulse;
            // LED 상태가 변할 때(켜지거나 꺼질 때) 2ms 동안만 소리
            if (turn_signal_pulse != prev_sig) begin
                click_timer <= 100_000; 
                click_en <= 1;
            end
            
            if (click_timer > 0) click_timer <= click_timer - 1;
            else click_en <= 0;
        end
    end

    // 톤 생성
    always @(posedge clk) begin
        if (is_horn) begin // 경적 (우선순위 1)
            if(tone_cnt >= 62500) begin tone_cnt<=0; wave<=~wave; end // 400Hz
            else tone_cnt<=tone_cnt+1;
        end else if (click_en) begin // 릴레이 소리 (우선순위 2)
            if(tone_cnt >= 25000) begin tone_cnt<=0; wave<=~wave; end // 1kHz
            else tone_cnt<=tone_cnt+1;
        end else begin
            wave <= 0;
        end
    end
    
    always @(*) piezo_out = wave;

endmodule