`timescale 1ns / 1ps

module Tb_Car_Simulator;

    // --- Inputs ---
    reg CLK;
    reg KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6;
    reg KEY_7, KEY_8, KEY_9, KEY_STAR, KEY_0, KEY_SHARP;
    reg [7:0] DIP_SW;
    reg SPI_DOUT; // MISO (ADC -> FPGA)

    // --- Outputs ---
    wire SPI_SCK, SPI_AD, SPI_DIN;
    wire [7:0] SEG_DATA, SEG_COM;
    wire PIEZO;
    wire [7:0] LED;
    wire LCD_RS, LCD_RW, LCD_E;
    wire [7:0] LCD_DATA;
    wire [7:0] SEG_1_DATA;
    wire [3:0] FC_RED, FC_GREEN, FC_BLUE;

    // --- Unit Under Test (UUT) ---
    Car_Simulator_Top uut (
        .CLK(CLK), 
        .KEY_1(KEY_1), .KEY_2(KEY_2), .KEY_3(KEY_3), .KEY_4(KEY_4), .KEY_5(KEY_5), .KEY_6(KEY_6), 
        .KEY_7(KEY_7), .KEY_8(KEY_8), .KEY_9(KEY_9), .KEY_STAR(KEY_STAR), .KEY_0(KEY_0), .KEY_SHARP(KEY_SHARP), 
        .DIP_SW(DIP_SW), 
        .SPI_SCK(SPI_SCK), .SPI_AD(SPI_AD), .SPI_DIN(SPI_DIN), .SPI_DOUT(SPI_DOUT), 
        .SEG_DATA(SEG_DATA), .SEG_COM(SEG_COM), 
        .PIEZO(PIEZO), 
        .LED(LED), 
        .LCD_RS(LCD_RS), .LCD_RW(LCD_RW), .LCD_E(LCD_E), .LCD_DATA(LCD_DATA), 
        .SEG_1_DATA(SEG_1_DATA), 
        .FC_RED(FC_RED), .FC_GREEN(FC_GREEN), .FC_BLUE(FC_BLUE)
    );

    // --- Clock Generation (50MHz) ---
    initial begin
        CLK = 0;
        forever #10 CLK = ~CLK; // 20ns period
    end

    // --- ADC Simulation Variables ---
    reg [11:0] analog_accel = 0; // 가상 악셀 값 (0~4095)
    reg [11:0] analog_cds = 2000; // 가상 조도 값 (어두움)

    // --- Monitoring ---
    always @(LED) begin
        $display("[Time: %0t] LED Changed: %b (L: %b, R: %b, Tail: %b)", $time, LED, LED[7:6], LED[1:0], LED[5:2]);
    end

    always @(SEG_DATA) begin
        // 7-Segment 데이터가 변할 때마다 출력하면 너무 많을 수 있으므로, 
        // 특정 조건이나 주기적으로 확인하는 것이 좋지만, 요청에 따라 변화를 감지합니다.
        // 여기서는 스캔 동작 때문에 계속 변하므로, 주요 이벤트 시점에만 값을 찍거나
        // 변화가 있을 때 간단히 로그를 남깁니다.
        // $display("[Time: %0t] SEG_DATA: %h, SEG_COM: %h", $time, SEG_DATA, SEG_COM);
    end

    always @(posedge KEY_3) $display("[Time: %0t] Key 3 Pressed (Gear P)", $time);
    always @(posedge KEY_6) $display("[Time: %0t] Key 6 Pressed (Gear R)", $time);
    always @(posedge KEY_9) $display("[Time: %0t] Key 9 Pressed (Gear N)", $time);
    always @(posedge KEY_SHARP) $display("[Time: %0t] Key # Pressed (Gear D)", $time);
    always @(posedge KEY_7) $display("[Time: %0t] Key 7 Pressed (Hard Brake)", $time);
    always @(posedge KEY_STAR) $display("[Time: %0t] Key * Pressed (Normal Brake)", $time);

    // 기어 상태 모니터링 (1-Digit Segment)
    always @(SEG_1_DATA) begin
        case (SEG_1_DATA)
            8'b0111_0011: $display("[Time: %0t] Gear Display: P", $time);
            8'b0101_0000: $display("[Time: %0t] Gear Display: R", $time);
            8'b0101_0100: $display("[Time: %0t] Gear Display: N", $time);
            8'b0101_1110: $display("[Time: %0t] Gear Display: D", $time);
            default: $display("[Time: %0t] Gear Display: Unknown (%b)", $time, SEG_1_DATA);
        endcase
    end

    always @(uut.adc_accel_w) begin
        $display("[Time: %0t] ADC Accel Value Changed: %d", $time, uut.adc_accel_w);
    end

    always @(uut.tick_spd) begin
        if(uut.tick_spd) $display("[Time: %0t] Speed Tick Triggered", $time);
    end

    // --- Internal Signal Monitoring (Speed, RPM, Gear, Engine) ---
    always @(uut.spd_w) begin
        $display("[Time: %0t] Speed Changed: %d km/h", $time, uut.spd_w);
    end

    always @(uut.rpm_w) begin
        $display("[Time: %0t] Engine RPM Changed: %d", $time, uut.rpm_w);
    end

    always @(uut.gear_reg) begin
        case(uut.gear_reg)
            4'd3: $display("[Time: %0t] Internal Gear State: P", $time);
            4'd6: $display("[Time: %0t] Internal Gear State: R", $time);
            4'd9: $display("[Time: %0t] Internal Gear State: N", $time);
            4'd12: $display("[Time: %0t] Internal Gear State: D", $time);
            default: $display("[Time: %0t] Internal Gear State: Unknown (%d)", $time, uut.gear_reg);
        endcase
    end

    always @(uut.global_safe_rst) begin
        if (uut.global_safe_rst) 
            $display("[Time: %0t] System Reset Active (Key OFF / Engine OFF Condition Met)", $time);
        else 
            $display("[Time: %0t] System Reset Released (Key ON / Engine Started)", $time);
    end

    always @(uut.ess_trig) begin
        if (uut.ess_trig) $display("[Time: %0t] ESS Triggered (Emergency Stop Signal)!", $time);
        else $display("[Time: %0t] ESS Deactivated", $time);
    end

    // --- LCD Monitoring ---
    always @(posedge uut.LCD_E) begin
        if (uut.LCD_E) begin
            if (uut.LCD_RS == 1) begin // Data Write
                $display("[Time: %0t] LCD Write Data: '%c' (Hex: %h)", $time, uut.LCD_DATA, uut.LCD_DATA);
            end else begin // Command Write
                $display("[Time: %0t] LCD Write Command: %h", $time, uut.LCD_DATA);
            end
        end
    end

    // --- Test Sequence ---
    initial begin
        // 1. 초기화
        init_inputs();
        
        // Force initialize internal signals to avoid 'x' propagation due to circular reset dependency
        force uut.u_logic.speed = 0;
        force uut.u_adc.adc_accel = 0;
        force uut.u_adc.adc_cds = 0;
        #100;
        release uut.u_logic.speed;
        release uut.u_adc.adc_accel;
        release uut.u_adc.adc_cds;
        
        $display("[Time: %0t] Simulation Started", $time);
        
        // 2. 시동 걸기 (안전 리셋 조건 달성)
        // 조건: KEY_8 + KEY_STAR + DIP_SW[7] + Gear=P(KEY_3) + Speed=0
        #1000;
        $display("[Time: %0t] Attempting Engine Start (Reset)...", $time);
        
        // 먼저 기어를 P로 설정
        KEY_3 = 1; #1000; KEY_3 = 0;
        #100;
        
        // 리셋 조건 입력 유지
        DIP_SW[7] = 1; // OBD Mode SW
        KEY_8 = 1;
        KEY_STAR = 1; // Brake Normal
        #500; // 리셋 신호 발생 대기
        
        // 리셋 해제
        KEY_8 = 0;
        KEY_STAR = 0;
        $display("[Time: %0t] Engine Started (Reset Complete)", $time);
        
        // 3. 키 입력 순차 테스트 (1 -> 2 -> ... -> #)
        $display("--- Testing All Keys Sequentially ---");
        press_key_input(1); // KEY_1 (Horn)
        press_key_input(2); // KEY_2
        press_key_input(3); // KEY_3 (Gear P)
        press_key_input(4); // KEY_4
        press_key_input(5); // KEY_5
        press_key_input(6); // KEY_6 (Gear R)
        press_key_input(7); // KEY_7 (Hard Brake)
        press_key_input(8); // KEY_8
        press_key_input(9); // KEY_9 (Gear N)
        press_key_input(0); // KEY_0
        press_key_input(10); // KEY_STAR (Normal Brake)
        press_key_input(11); // KEY_SHARP (Gear D)
        $display("--- Key Test Complete ---");
        
        // 4. 가속 테스트 (D 기어 상태여야 함)
        $display("[Time: %0t] Accelerating Test Start...", $time);
        
        // Phase 1: Low Acceleration (Accel=1000 -> ADC~62)
        $display("[Time: %0t] Step 1: Low Acceleration (Accel=1000)", $time);
        analog_accel = 1000; 
        repeat(30) begin // 1.5 second
            #50000000; 
            $display("[Time: %0t] Speed: %d km/h, RPM: %d, Accel(ADC): %d", $time, uut.spd_w, uut.rpm_w, uut.adc_accel_w);
        end

        // Phase 2: High Acceleration (Accel=4000 -> ADC~250)
        $display("[Time: %0t] Step 2: High Acceleration (Accel=4000)", $time);
        analog_accel = 4000; 
        repeat(30) begin // 1.5 second
            #50000000; 
            $display("[Time: %0t] Speed: %d km/h, RPM: %d, Accel(ADC): %d", $time, uut.spd_w, uut.rpm_w, uut.adc_accel_w);
        end

        // Phase 3: Coasting (Accel=0)
        $display("[Time: %0t] Step 3: Coasting (Accel=0)", $time);
        analog_accel = 0; 
        repeat(20) begin // 1 second
            #50000000; 
            $display("[Time: %0t] Speed: %d km/h, RPM: %d, Accel(ADC): %d", $time, uut.spd_w, uut.rpm_w, uut.adc_accel_w);
        end
        
        // 5. 급제동 (ESS 테스트)
        $display("[Time: %0t] Hard Braking! (ESS Trigger)", $time);
        analog_accel = 0; // 악셀 뗌
        KEY_7 = 1; // 급브레이크
        #40000000; // 브레이크 유지 (40ms)
        KEY_7 = 0;
        
        // ESS 깜빡임 확인을 위해 대기 (3초)
        repeat(60) #50000000; // 50ms * 60 = 3s
        
        $display("[Time: %0t] Simulation Finished", $time);
        $finish;
    end

    // --- Helper Tasks ---
    task init_inputs;
        begin
            KEY_1=0; KEY_2=0; KEY_3=0; KEY_4=0; KEY_5=0; KEY_6=0;
            KEY_7=0; KEY_8=0; KEY_9=0; KEY_STAR=0; KEY_0=0; KEY_SHARP=0;
            DIP_SW=0;
            SPI_DOUT=0;
        end
    endtask

    task press_key_3; // P Gear
        begin
            KEY_3 = 1; #1000; KEY_3 = 0;
        end
    endtask

    task press_key_sharp; // D Gear
        begin
            KEY_SHARP = 1; #1000; KEY_SHARP = 0;
        end
    endtask

    task press_key_input;
        input [3:0] k;
        begin
            case(k)
                1: KEY_1 = 1;
                2: KEY_2 = 1;
                3: KEY_3 = 1;
                4: KEY_4 = 1;
                5: KEY_5 = 1;
                6: KEY_6 = 1;
                7: KEY_7 = 1;
                8: KEY_8 = 1;
                9: KEY_9 = 1;
                10: KEY_STAR = 1;
                0: KEY_0 = 1;
                11: KEY_SHARP = 1;
            endcase
            $display("[Time: %0t] Key %d Pressed", $time, k);
            #2000000; // 40ms Press
            
            case(k)
                1: KEY_1 = 0;
                2: KEY_2 = 0;
                3: KEY_3 = 0;
                4: KEY_4 = 0;
                5: KEY_5 = 0;
                6: KEY_6 = 0;
                7: KEY_7 = 0;
                8: KEY_8 = 0;
                9: KEY_9 = 0;
                10: KEY_STAR = 0;
                0: KEY_0 = 0;
                11: KEY_SHARP = 0;
            endcase
            $display("[Time: %0t] Key %d Released", $time, k);
            #2000000; // Wait
        end
    endtask

    // --- SPI Slave Model (ADC Emulator) ---
    // FPGA가 Master로서 CLK과 MOSI를 보내면, 이 블록이 ADC처럼 동작하여 MISO로 값을 보냄
    reg [11:0] adc_shift_out;
    reg [4:0] spi_bit_cnt;
    reg [2:0] spi_cmd_reg; // Start, SGL, CH
    
    always @(negedge SPI_AD) begin // CS Falling Edge (Start Transaction)
        spi_bit_cnt = 0;
        spi_cmd_reg = 0;
    end

    always @(posedge SPI_SCK) begin // Rising Edge: FPGA reads MISO, ADC reads MOSI
        // ADC reads MOSI
        if (spi_bit_cnt < 5) begin
            spi_cmd_reg = {spi_cmd_reg[1:0], SPI_DIN};
        end
    end

    always @(negedge SPI_SCK) begin // Falling Edge: ADC updates MISO
        if (SPI_AD == 0) begin
            // Protocol: Start(1), SGL(1), CH(1), MSBF(1), Null(1) -> Total 5 bits input before data
            // Simplified Model:
            // After 4th clock (MSBF), ADC prepares data.
            // 5th clock falling edge: Output Null bit (0)
            // 6th clock falling edge: Output B11
            
            if (spi_bit_cnt == 4) begin
                // Determine Channel from captured command
                // Command sequence received: Start, SGL, CH, MSBF
                // We just look at the 'CH' bit which was the 3rd bit received.
                // But for simplicity, let's just toggle based on the command bit.
                // Let's assume correct timing.
                
                // Check Channel (spi_cmd_reg[1] corresponds to CH bit roughly)
                // Actually, let's just use the global analog variables directly for simplicity
                // If FPGA sent CH0 command, we send accel. If CH1, send CDS.
                // Since we can't easily decode perfectly in this simple model, 
                // we will alternate or just send accel for now as it's the main test.
                
                // Let's try to decode properly:
                // Bit 0: Start
                // Bit 1: SGL
                // Bit 2: CH
                // Bit 3: MSBF
                // We are at count 4.
                
                if (spi_cmd_reg[1] == 1) adc_shift_out = analog_cds; // CH1
                else adc_shift_out = analog_accel; // CH0
            end
            
            if (spi_bit_cnt >= 4 && spi_bit_cnt <= 16) begin
                if (spi_bit_cnt == 4) SPI_DOUT = 0; // Null Bit
                else begin
                    SPI_DOUT = adc_shift_out[11]; // MSB First
                    adc_shift_out = {adc_shift_out[10:0], 1'b0};
                end
            end else begin
                SPI_DOUT = 0; // High-Z usually
            end
            
            spi_bit_cnt = spi_bit_cnt + 1;
        end
    end

endmodule
