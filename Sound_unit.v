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
    // 1. Reverse Warning Sound ("Fur Elise")
    // =========================================================
    // Frequencies (50MHz / (Freq * 2))
    localparam NOTE_C4  = 95554;
    localparam NOTE_E4  = 75842;
    localparam NOTE_GS4 = 60197;
    localparam NOTE_A4  = 56818;
    localparam NOTE_B4  = 50619;
    localparam NOTE_C5  = 47778;
    localparam NOTE_D5  = 42565;
    localparam NOTE_DS5 = 40176;
    localparam NOTE_E5  = 37921;
    localparam NOTE_REST = 0;

    reg [5:0] note_idx; // Increased to 6 bits for longer melody
    reg [24:0] note_timer; 
    reg [19:0] current_tone_period;
    reg reverse_melody_active; 

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            note_idx <= 0;
            note_timer <= 0;
            current_tone_period <= 0;
            reverse_melody_active <= 0;
        end else begin
            if (is_reverse && engine_on) begin
                reverse_melody_active <= 1;
                
                // 0.25 sec per note (12,500,000) - Slower
                if (note_timer >= 12_500_000) begin
                    note_timer <= 0;
                    if (note_idx >= 45) note_idx <= 0; // Loop
                    else note_idx <= note_idx + 1;
                end else begin
                    note_timer <= note_timer + 1;
                end

                case (note_idx)
                    // Phrase 1
                    0: current_tone_period <= NOTE_E5;
                    1: current_tone_period <= NOTE_DS5;
                    2: current_tone_period <= NOTE_E5;
                    3: current_tone_period <= NOTE_DS5;
                    4: current_tone_period <= NOTE_E5;
                    5: current_tone_period <= NOTE_B4;
                    6: current_tone_period <= NOTE_D5;
                    7: current_tone_period <= NOTE_C5;
                    8: current_tone_period <= NOTE_A4;
                    9: current_tone_period <= NOTE_A4; // Hold
                    10: current_tone_period <= NOTE_REST;
                    
                    // Phrase 2
                    11: current_tone_period <= NOTE_C4;
                    12: current_tone_period <= NOTE_E4;
                    13: current_tone_period <= NOTE_A4;
                    14: current_tone_period <= NOTE_B4;
                    15: current_tone_period <= NOTE_B4; // Hold
                    16: current_tone_period <= NOTE_REST;

                    // Phrase 3
                    17: current_tone_period <= NOTE_E4;
                    18: current_tone_period <= NOTE_GS4;
                    19: current_tone_period <= NOTE_B4;
                    20: current_tone_period <= NOTE_C5;
                    21: current_tone_period <= NOTE_C5; // Hold
                    22: current_tone_period <= NOTE_REST;

                    // Phrase 4 (Repeat Phrase 1)
                    23: current_tone_period <= NOTE_E4;
                    24: current_tone_period <= NOTE_E5;
                    25: current_tone_period <= NOTE_DS5;
                    26: current_tone_period <= NOTE_E5;
                    27: current_tone_period <= NOTE_DS5;
                    28: current_tone_period <= NOTE_E5;
                    29: current_tone_period <= NOTE_B4;
                    30: current_tone_period <= NOTE_D5;
                    31: current_tone_period <= NOTE_C5;
                    32: current_tone_period <= NOTE_A4;
                    33: current_tone_period <= NOTE_A4; // Hold
                    34: current_tone_period <= NOTE_REST;

                    // Phrase 5 (Ending)
                    35: current_tone_period <= NOTE_C4;
                    36: current_tone_period <= NOTE_E4;
                    37: current_tone_period <= NOTE_A4;
                    38: current_tone_period <= NOTE_B4;
                    39: current_tone_period <= NOTE_B4; // Hold
                    40: current_tone_period <= NOTE_REST;
                    
                    41: current_tone_period <= NOTE_E4;
                    42: current_tone_period <= NOTE_C5;
                    43: current_tone_period <= NOTE_B4;
                    44: current_tone_period <= NOTE_A4;
                    45: current_tone_period <= NOTE_A4; // Hold (End of loop)

                    default: current_tone_period <= NOTE_REST;
                endcase
            end else begin
                reverse_melody_active <= 0;
                note_idx <= 0;
                note_timer <= 0;
                current_tone_period <= 0;
            end
        end
    end

    reg [19:0] reverse_tone_cnt;
    reg reverse_wave;
    
    always @(posedge clk) begin
        if (reverse_melody_active && current_tone_period > 0) begin
            // [Volume Control] Use Low Duty Cycle instead of 50%
            // Count up to full period (current_tone_period * 2)
            if (reverse_tone_cnt >= (current_tone_period << 1)) begin 
                reverse_tone_cnt <= 0;
            end else reverse_tone_cnt <= reverse_tone_cnt + 1;
            
            // Output High for 1/8 of the period (12.5% Duty Cycle)
            reverse_wave <= (reverse_tone_cnt < (current_tone_period >> 2));
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
    wire [15:0] click_limit = (is_tick ? 12500 : 15625);

    // Two-tone for Click (Tick: 2kHz, Tock: 1.6kHz)
    always @(posedge clk) begin
        if (click_sound_active) begin
            // [Volume Control] Low Duty Cycle
            if (click_tone_cnt >= (click_limit << 1)) begin 
                click_tone_cnt <= 0;
            end else click_tone_cnt <= click_tone_cnt + 1;
            
            // 12.5% Duty Cycle
            click_wave <= (click_tone_cnt < (click_limit >> 2));
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
            // 400Hz Low Tone -> Period 125,000
            if (horn_cnt >= 125000) begin
                horn_cnt <= 0;
            end else horn_cnt <= horn_cnt + 1;
            
            // [Volume Control] 25% Duty Cycle (Horn is louder)
            horn_wave <= (horn_cnt < 31250);
        end else begin
            horn_wave <= 0;
            horn_cnt <= 0;
        end
    end

    // =========================================================
    // 4. Engine Sound (RPM based)
    // =========================================================
    reg [19:0] engine_cnt;
    reg [19:0] engine_period;
    reg engine_wave;

    always @(posedge clk) begin
        if (engine_on) begin
            // Simple RPM to Period mapping (Linear approximation)
            // Higher RPM -> Lower Period -> Higher Pitch
            // [Modified] Lowered base pitch significantly for idle (Speed 0).
            // Base (0 RPM) -> 750,000 (~33Hz)
            // Max (8000 RPM) -> 750,000 - (8000 * 75) = 150,000 (~166Hz)
            if (rpm > 8000) engine_period <= 100000; // Safety clamp
            else engine_period <= 400000 - (rpm * 50);

            // [Volume Control] Very Low Duty Cycle for Engine (Subtle background)
            if (engine_cnt >= (engine_period << 1)) begin
                engine_cnt <= 0;
            end else begin
                engine_cnt <= engine_cnt + 1;
            end
            
            // 6.25% Duty Cycle (Shift 4) - Fixed mismatch between comment and code
            engine_wave <= (engine_cnt < (engine_period >> 4));
        end else begin
            engine_wave <= 0;
            engine_cnt <= 0;
        end
    end

    // =========================================================
    // 5. Sound Priority Mux
    // =========================================================
    always @(*) begin
        if (is_horn) begin
            piezo_out = horn_wave; // Priority 1: Horn
        end 
        else if (click_sound_active) begin
            piezo_out = click_wave; // Priority 2: Turn Signal Click
        end 
        else if (reverse_melody_active) begin
            piezo_out = reverse_wave; // Priority 3: Reverse Melody
        end
        else if (engine_on) begin
            piezo_out = engine_wave; // Priority 4: Engine Sound
        end
        else begin
            piezo_out = 1'b0; // Silence
        end
    end

endmodule