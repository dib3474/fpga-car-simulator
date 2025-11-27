module Sound_Unit (
    input clk,              // 50MHz System Clock
    input rst,              // Reset
    
    input [13:0] rpm,       // RPM (엔진음 톤 결정)
    input ess_active,       // ESS (비상등)
    input is_horn,          // 경적
    input turn_signal_on,   // 깜빡이 켜짐 여부 (LED 상태)
    
    output reg piezo_out    // 부저 출력
);

    // =========================================================
    // 1. 엔진음 생성을 위한 LFSR (Linear Feedback Shift Register)
    // 백색소음(White Noise)을 만들어 "쉬이익" 하는 소리를 냅니다.
    // =========================================================
    reg [15:0] lfsr;
    wire lfsr_feedback;
    assign lfsr_feedback = lfsr[0] ^ lfsr[2] ^ lfsr[3] ^ lfsr[5];

    reg [19:0] engine_cnt;
    reg [19:0] engine_period;
    reg engine_sound_bit;

    // RPM에 따른 엔진음 주기 계산 (RPM이 높을수록 주기가 짧아짐 = 고음)
    // 소리를 부드럽게 하기 위해 주파수 대역을 낮춤
    always @(*) begin
        if (rpm < 500) engine_period = 0; // 시동 꺼짐 혹은 극저회전
        else engine_period = 150000 - (rpm * 10); // 기본값에서 RPM만큼 뺌
    end

    // 엔진음 생성 로직
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= 16'hACE1; // 초기 시드값 (0이면 안됨)
            engine_cnt <= 0;
            engine_sound_bit <= 0;
        end else begin
            if (engine_period != 0) begin
                if (engine_cnt >= engine_period) begin
                    engine_cnt <= 0;
                    // LFSR 시프트 (랜덤값 생성)
                    lfsr <= {lfsr_feedback, lfsr[15:1]};
                    // 랜덤 비트를 출력하여 "치직" 거리는 소리 생성
                    engine_sound_bit <= lfsr[0]; 
                end else begin
                    engine_cnt <= engine_cnt + 1;
                end
            end else begin
                engine_sound_bit <= 0;
            end
        end
    end

    // =========================================================
    // 2. 깜빡이 소리 ("똑-깍" 릴레이 사운드 구현)
    // =========================================================
    // 깜빡이(LED)가 켜지는 순간(Rising Edge)에만 짧게 "틱" 소리를 냄
    reg prev_turn_signal;
    reg [19:0] click_cnt;
    reg click_sound_active;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_turn_signal <= 0;
            click_cnt <= 0;
            click_sound_active <= 0;
        end else begin
            prev_turn_signal <= turn_signal_on;
            
            // LED가 꺼져있다가 켜지는 순간 (0->1) 또는 켜져있다가 꺼지는 순간 (1->0) 감지
            // 실제 릴레이는 붙을 때 한번, 떨어질 때 한번 소리가 남
            if (turn_signal_on != prev_turn_signal) begin
                click_cnt <= 150_000; // 소리 지속 시간 (약 3ms) - 아주 짧게 "틱"
                click_sound_active <= 1;
            end
            
            if (click_cnt > 0) begin
                click_cnt <= click_cnt - 1;
                click_sound_active <= 1; // 카운트 도는 동안 소리 냄
            end else begin
                click_sound_active <= 0;
            end
        end
    end
    
    // "틱" 소리의 톤 (주파수) 생성
    reg [15:0] click_tone_cnt;
    reg click_wave;
    always @(posedge clk) begin
        if (click_sound_active) begin
            // 약 1kHz 톤으로 "틱"
            if (click_tone_cnt >= 25000) begin 
                click_tone_cnt <= 0;
                click_wave <= ~click_wave;
            end else click_tone_cnt <= click_tone_cnt + 1;
        end else begin
            click_wave <= 0;
            click_tone_cnt <= 0;
        end
    end

    // =========================================================
    // 3. 경적 소리 (부드러운 저음 톤)
    // =========================================================
    reg [19:0] horn_cnt;
    reg horn_wave;
    
    always @(posedge clk) begin
        if (is_horn) begin
            // 약 400Hz (저음)
            if (horn_cnt >= 62500) begin
                horn_cnt <= 0;
                horn_wave <= ~horn_wave;
            end else horn_cnt <= horn_cnt + 1;
        end else begin
            horn_wave <= 0;
            horn_cnt <= 0;
        end
    end

    // =========================================================
    // 4. 최종 출력 믹싱 (우선순위 결정)
    // =========================================================
    always @(*) begin
        if (is_horn) begin
            piezo_out = horn_wave; // 1순위: 경적
        end 
        else if (click_sound_active) begin
            piezo_out = click_wave; // 2순위: 깜빡이/비상등 클릭음
        end 
        else begin
            piezo_out = engine_sound_bit; // 3순위: 엔진음 (백색소음)
        end
    end

endmodule