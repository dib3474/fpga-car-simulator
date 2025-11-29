module Sound_Unit (
    input clk,              // 50MHz System Clock
    input rst,              // Reset
    
    input [13:0] rpm,       // RPM (Unused for sound now)
    input ess_active,       // ESS (Unused)
    input is_horn,          // Horn
    input is_reverse,       // Reverse Gear (R)
    input turn_signal_on,   // Turn Signal Blink State
    input engine_on,        // Engine State
    input accel_active,     // Accel State (Unused)
    
    output reg piezo_out    // Piezo Output
);

    // =========================================================
    // 1. Reverse Warning Sound ("Beep- Beep-")
    // =========================================================
    reg [25:0] reverse_cnt; // Counter for 1Hz cycle (0.5s ON, 0.5s OFF)
    reg reverse_beep_en;    // Enable beep during ON time
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reverse_cnt <= 0;
            reverse_beep_en <= 0;
        end else begin
            if (is_reverse && engine_on) begin
                if (reverse_cnt >= 50_000_000) reverse_cnt <= 0; // 1 second period
                else reverse_cnt <= reverse_cnt + 1;
                
                // Beep for first 0.5 sec
                reverse_beep_en <= (reverse_cnt < 25_000_000);
            end else begin
                reverse_cnt <= 0;
                reverse_beep_en <= 0;
            end
        end
    end

    reg [15:0] reverse_tone_cnt;
    reg reverse_wave;
    // 1kHz Tone for Reverse
    always @(posedge clk) begin
        if (reverse_beep_en) begin
            if (reverse_tone_cnt >= 25000) begin 
                reverse_tone_cnt <= 0;
                reverse_wave <= ~reverse_wave;
            end else reverse_tone_cnt <= reverse_tone_cnt + 1;
        end else begin
            reverse_wave <= 0;
            reverse_tone_cnt <= 0;
        end
    end

    // =========================================================
    // 2. Turn Signal Click Sound ("Tick- Tock-")
    // =========================================================
    reg prev_turn_signal;
    reg [19:0] click_cnt;
    reg click_sound_active;
    reg is_tick; // 1=Tick (High), 0=Tock (Low)
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_turn_signal <= 0;
            click_cnt <= 0;
            click_sound_active <= 0;
            is_tick <= 0;
        end else begin
            prev_turn_signal <= turn_signal_on;
            
            // Trigger sound on both edges (ON->OFF, OFF->ON)
            if (turn_signal_on != prev_turn_signal) begin
                click_cnt <= 150_000; // 3ms duration
                click_sound_active <= 1;
                is_tick <= turn_signal_on; // Rising=Tick, Falling=Tock
            end
            
            if (click_cnt > 0) begin
                click_cnt <= click_cnt - 1;
                click_sound_active <= 1;
            end else begin
                click_sound_active <= 0;
            end
        end
    end
    
    reg [15:0] click_tone_cnt;
    reg click_wave;
    // Two-tone for Click (Tick: 2kHz, Tock: 1.6kHz)
    always @(posedge clk) begin
        if (click_sound_active) begin
            // 2kHz -> 12500, 1.6kHz -> 15625
            if (click_tone_cnt >= (is_tick ? 12500 : 15625)) begin 
                click_tone_cnt <= 0;
                click_wave <= ~click_wave;
            end else click_tone_cnt <= click_tone_cnt + 1;
        end else begin
            click_wave <= 0;
            click_tone_cnt <= 0;
        end
    end

    // =========================================================
    // 3. Horn Sound ("Honk!")
    // =========================================================
    reg [19:0] horn_cnt;
    reg horn_wave;
    
    always @(posedge clk) begin
        if (is_horn) begin
            // 400Hz Low Tone
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
    // 4. Sound Priority Mux
    // =========================================================
    always @(*) begin
        if (is_horn) begin
            piezo_out = horn_wave; // Priority 1: Horn
        end 
        else if (click_sound_active) begin
            piezo_out = click_wave; // Priority 2: Turn Signal Click
        end 
        else if (reverse_beep_en) begin
            piezo_out = reverse_wave; // Priority 3: Reverse Beep
        end
        else begin
            piezo_out = 1'b0; // Silence (Engine sound removed)
        end
    end

endmodule