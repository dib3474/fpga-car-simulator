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
            if (reverse_tone_cnt >= current_tone_period) begin 
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
        else if (reverse_melody_active) begin
            piezo_out = reverse_wave; // Priority 3: Reverse Melody
        end
        else begin
            piezo_out = 1'b0; // Silence (Engine sound removed)
        end
    end

endmodule