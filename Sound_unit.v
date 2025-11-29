module Sound_Unit (
    input clk,              // 50MHz System Clock
    input rst,              // Reset
    
    input [13:0] rpm,       // RPM (������ �� ����)
    input ess_active,       // ESS (����)
    input is_horn,          // ����
    input turn_signal_on,   // ������ ���� ���� (LED ����)
    input engine_on,
    input accel_active,
    
    output reg piezo_out    // ���� ���
);

    // =========================================================
    // 1. ������ ������ ���� LFSR (Linear Feedback Shift Register)
    // �������(White Noise)�� ����� "������" �ϴ� �Ҹ��� ���ϴ�.
    // =========================================================
    reg [15:0] lfsr;
    wire lfsr_feedback;
    assign lfsr_feedback = lfsr[0] ^ lfsr[2] ^ lfsr[3] ^ lfsr[5];

    reg [19:0] engine_cnt;
    reg [19:0] engine_period;
    reg engine_sound_bit;

    // RPM�� ���� ������ �ֱ� ��� (RPM�� �������� �ֱⰡ ª���� = ����)
    // �Ҹ��� �ε巴�� �ϱ� ���� ���ļ� �뿪�� ����
    always @(*) begin
        if ((rpm < 500) || !engine_on || !accel_active) engine_period = 0; // �õ� ���� Ȥ�� ����ȸ��
        else engine_period = 150000 - (rpm * 10); // �⺻������ RPM��ŭ ��
    end

    // ������ ���� ����
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= 16'hACE1; // �ʱ� �õ尪 (0�̸� �ȵ�)
            engine_cnt <= 0;
            engine_sound_bit <= 0;
        end else begin
            if (engine_period != 0) begin
                if (engine_cnt >= engine_period) begin
                    engine_cnt <= 0;
                    // LFSR ����Ʈ (������ ����)
                    lfsr <= {lfsr_feedback, lfsr[15:1]};
                    // ���� ��Ʈ�� ����Ͽ� "ġ��" �Ÿ��� �Ҹ� ����
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
    // 2. ������ �Ҹ� ("��-��" ������ ���� ����)
    // =========================================================
    // ������(LED)�� ������ ����(Rising Edge)���� ª�� "ƽ" �Ҹ��� ��
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
            
            // LED�� �����ִٰ� ������ ���� (0->1) �Ǵ� �����ִٰ� ������ ���� (1->0) ����
            // ���� �����̴� ���� �� �ѹ�, ������ �� �ѹ� �Ҹ��� ��
            if (turn_signal_on != prev_turn_signal) begin
                click_cnt <= 150_000; // �Ҹ� ���� �ð� (�� 3ms) - ���� ª�� "ƽ"
                click_sound_active <= 1;
            end
            
            if (click_cnt > 0) begin
                click_cnt <= click_cnt - 1;
                click_sound_active <= 1; // ī��Ʈ ���� ���� �Ҹ� ��
            end else begin
                click_sound_active <= 0;
            end
        end
    end
    
    // "ƽ" �Ҹ��� �� (���ļ�) ����
    reg [15:0] click_tone_cnt;
    reg click_wave;
    always @(posedge clk) begin
        if (click_sound_active) begin
            // �� 1kHz ������ "ƽ"
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
    // 3. ���� �Ҹ� (�ε巯�� ���� ��)
    // =========================================================
    reg [19:0] horn_cnt;
    reg horn_wave;
    
    always @(posedge clk) begin
        if (is_horn) begin
            // �� 400Hz (����)
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
    // 4. ���� ��� �ͽ� (�켱���� ����)
    // =========================================================
    always @(*) begin
        if (is_horn) begin
            piezo_out = horn_wave; // 1����: ����
        end 
        else if (click_sound_active) begin
            piezo_out = click_wave; // 2����: ������/���� Ŭ����
        end 
        else begin
            if (engine_on && accel_active) piezo_out = engine_sound_bit; // 3����: ������ (�������)
            else piezo_out = 1'b0;
        end
    end

endmodule