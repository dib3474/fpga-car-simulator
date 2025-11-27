# 🚗 FPGA Car Simulator (자동차 주행 시뮬레이터)

**2025 논리회로설계및실험 텀프로젝트 (7조)**

**Target Board:** Hanback HBE-Combo II-DLD  
**Language:** Verilog HDL

## 📖 프로젝트 개요

이 프로젝트는 **Verilog HDL**을 사용하여 실제 자동차의 주행 메커니즘을 FPGA 보드 상에서 시뮬레이션하는 시스템입니다.  
사용자는 키패드, ADC(가속 페달), DIP 스위치를 통해 차량을 조작하며, 차량의 상태(속도, RPM, 기어, 안전 경고)는 7-Segment, LCD, LED, 모터를 통해 실시간으로 출력됩니다.

## 👥 팀원 (Team 7)

- **문수호:**
- **이도헌:**

## ✨ 주요 기능 (Key Features)

1.  **엔진 및 기어 제어 (Engine & Transmission)**

    - 자동 변속기 시뮬레이션 (P, R, N, D 기어 변속)
    - 주행 속도에 따른 가변 RPM 시뮬레이션

2.  **주행 물리 엔진 (Vehicle Dynamics)**

    - **가속:** ADC 값(페달 압력)에 비례한 가속
    - **감속:** 일반 브레이크 및 급브레이크 구현
    - **ESS (Emergency Stop Signal):** 주행 중 급제동 시 비상등 자동 점멸 기능
    - 관성 주행 및 오르막/내리막 저항 시뮬레이션

3.  **안전 및 편의 시스템 (Safety & Warning)**
    - **후방 감지:** 후진(R) 시 조도 센서를 이용한 후방 물체 감지 및 경고음 출력
    - **방향지시등:** 좌/우 방향지시등 및 비상등 제어 (LED Blink)
    - **정보 표시:** LCD를 통한 텍스트 상태 정보(Status, Gear Mode) 출력

## 🛠️ 하드웨어 구성 및 핀맵 (Hardware & Pinmap)

| Module     | Component           | Description                                |
| :--------- | :------------------ | :----------------------------------------- |
| **Input**  | Keypad (3x4)        | 기어 변속, 브레이크 조작                   |
|            | DIP Switch          | 방향지시등, 비상등 제어                    |
|            | ADC (VR)            | 가속 페달 및 시동 키 역할                  |
|            | Light Sensor        | 후방 장애물 감지 센서                      |
| **Output** | 7-Segment (8-digit) | RPM (좌측 4자리) / 속도 (우측 4자리) 표시  |
|            | LCD (16x2)          | 시스템 상태 텍스트 출력 (Engine On/Off 등) |
|            | LED (8-bit)         | 방향지시등 및 ESS 점멸 표시                |
|            | Piezo Buzzer        | 후방 경고음, 시스템 알림음                 |
|            | Motor               | 속도계 아날로그 표시 (PWM 제어)            |

## 🎮 조작 방법 (Controls)

### 1. 키패드 (Keypad) 매핑

|  Key   | 기능 (Function)             | 비고                       |
| :----: | :-------------------------- | :------------------------- |
| **0**  | **Key On**                  | 시동 준비                  |
| **3**  | **P (Parking)**             | 주차 기어                  |
| **6**  | **R (Reverse)**             | 후진 기어 (후방 센서 작동) |
| **9**  | **N (Neutral)**             | 중립 기어                  |
| **#**  | **D (Drive)**               | 주행 기어                  |
| **7**  | **급브레이크 (Hard Brake)** | 급감속 + 비상등(ESS) 점멸  |
| **\*** | **브레이크 (Normal Brake)** | 일반 감속                  |

### 2. 기타 조작

- **가속 (Accelerator):** ADC 노브를 시계 방향으로 돌려 가속.
- **시동 (Ignition):** ADC 노브를 일정 수준 이상 돌려 `Engine On` 상태로 전환.
- **방향지시등:** DIP Switch 1(좌), 2(우), 3(비상등).

## 📂 프로젝트 구조 (Architecture)

프로젝트는 기능별로 모듈화되어 있습니다.

```bash
.
├── top_car_simulator.v    # 최상위 모듈 (Pin 연결 및 모듈 통합)
├── vehicle_dynamics.v     # 물리 엔진 (속도, RPM, 연료, ESS 계산)
├── main_fsm.v             # 기어 및 시동 상태 제어 (FSM)
├── lcd_driver.v           # LCD 텍스트 출력 드라이버
├── display_driver.v       # 7-Segment 및 LED 제어
├── keypad_scanner.v       # 키패드 입력 스캔 및 디코딩
├── tick_gen.v             # 시스템 클럭 분주 및 타이밍 생성
└── README.md              # 프로젝트 설명서
```
