# FPGA 기반 실시간 이미지 프로세싱 시스템 (Real-Time Image Processing System on FPGA)

## 1. 프로젝트 개요 (Project Overview)

본 프로젝트는 **FPGA(Field-Programmable Gate Array)**를 활용하여 카메라로부터 입력받은 영상을 실시간으로 처리하고 VGA 모니터로 출력하는 고성능 비전 시스템입니다. 소프트웨어 기반 처리가 아닌 **하드웨어 가속(Hardware Acceleration)**을 통해 640x480 해상도의 영상을 60fps로 지연 없이 처리하며, 엣지 검출, 컬러 트래킹, 배경 제거 등 다양한 컴퓨터 비전 알고리즘을 파이프라인 아키텍처로 구현하였습니다.

*   **개발 기간**: 2025.10 ~ 2025.12 (3개월)
*   **참여 인원**: 1인 (개인 프로젝트)
*   **주요 역할**: 전체 시스템 아키텍처 설계, Verilog HDL 모듈 구현, 시뮬레이션 검증, 하드웨어 디버깅

## 2. 기술 스택 (Technical Specifications)

### Hardware
*   **FPGA Board**: Altera Cyclone IV (DE2-115 / DE0-Nano 호환)
*   **Camera Sensor**: OmniVision OV7670 (CMOS Image Sensor)
*   **Display**: Standard VGA Monitor (640x480 @ 60Hz)
*   **Interface**: I2C (SCCB), GPIO, VGA Analog Interface

### Software & Tools
*   **Language**: Verilog HDL (RTL Design), Python (Image Verification)
*   **IDE**: Intel Quartus Prime Lite 20.1
*   **Simulation**: ModelSim / QuestaSim
*   **Version Control**: Git / GitHub

## 3. 시스템 아키텍처 (System Architecture)

전체 시스템은 **입력(Capture) → 저장(Buffer) → 처리(Processing) → 출력(Display)**의 4단계 파이프라인으로 구성되어 있습니다.

### 3.1. Image Capture & Downscaling
*   **OV7670 Controller**: I2C 프로토콜을 통해 카메라 레지스터를 설정하여 RGB565 포맷으로 데이터를 수신합니다.
*   **Hardware Downscaling**: 640x480 입력을 320x240으로 실시간 축소(2x2 Averaging)하여 메모리 사용량을 최적화했습니다.

### 3.2. Dual-Port Frame Buffer
*   **Ping-Pong Buffering**: 읽기/쓰기 충돌 방지를 위해 듀얼 포트 RAM을 사용하여 핑퐁 버퍼 구조를 구현했습니다.
*   **Clock Domain Crossing (CDC)**: 카메라 클럭(24MHz)과 VGA 클럭(25MHz) 간의 비동기 데이터 전송을 안정적으로 처리했습니다.

### 3.3. Image Processing Pipeline
모든 이미지 처리 모듈은 **스트리밍 방식**으로 동작하며, `PIPE_LATENCY` 파라미터를 통해 전체 파이프라인의 동기화를 유지합니다.

1.  **Gaussian Blur**: 3x3 윈도우 연산을 통해 노이즈를 제거합니다.
2.  **Sobel Edge Detection**: 수평/수직 그래디언트를 계산하여 엣지를 검출합니다.
3.  **Canny Edge Detection**: Non-maximum Suppression과 Hysteresis Thresholding을 하드웨어로 구현하여 정교한 엣지를 추출합니다.
4.  **Color Tracking**: RGB 색상 공간을 HSV로 실시간 변환하여 특정 색상(Red, Green, Blue)을 추적합니다.
5.  **Adaptive Background Subtraction**: 초기 프레임을 배경으로 저장하고, 현재 프레임과 비교하여 움직이는 물체만 분리합니다.

### 3.4. VGA Display Controller
*   **Upscaling**: 처리된 320x240 영상을 Nearest Neighbor 방식으로 640x480으로 업스케일링하여 출력합니다.
*   **Mode Selection**: IR 리모컨 입력을 받아 실시간으로 필터 모드(Original, Gray, Sobel, Canny, Color, Background)를 전환합니다.

## 4. 기술적 도전과 해결 (Engineering Challenges & Solutions)

### Challenge 1: 파이프라인 레이턴시 동기화 (Pipeline Latency Synchronization)
*   **문제**: 각 필터 모듈(Gaussian, Sobel 등)마다 연산에 소요되는 클럭 사이클이 달라, 최종 출력 시 픽셀 데이터와 동기 신호(Sync)가 어긋나는 현상 발생.
*   **해결**: `PIPE_LATENCY` 파라미터를 정의하고, 지연이 짧은 신호 경로에 Shift Register 기반의 Delay Chain을 추가하여 모든 경로의 지연 시간을 7 클럭으로 통일했습니다. 이를 통해 화면 떨림이나 픽셀 밀림 현상을 완벽하게 제거했습니다.

### Challenge 2: 실시간 메모리 대역폭 제한 (Memory Bandwidth)
*   **문제**: 단일 RAM 블록에서 읽기와 쓰기를 동시에 수행할 때 대역폭 부족으로 인한 병목 현상 발생.
*   **해결**: FPGA 내부의 M9K 블록 램을 활용하여 **Dual-Port RAM**을 구성하고, 읽기/쓰기 주소를 분리하여 동시 접근이 가능하도록 설계했습니다. 또한, 16비트 RGB565 데이터를 효율적으로 저장하기 위해 메모리 비트 폭을 최적화했습니다.

### Challenge 3: 복잡한 연산의 하드웨어 구현 (Complex Algorithm Implementation)
*   **문제**: Canny Edge Detection과 같은 복잡한 알고리즘은 나눗셈이나 제곱근 연산이 필요하여 하드웨어 자원을 많이 소모함.
*   **해결**:
    *   **근사화(Approximation)**: $ \sqrt{Gx^2 + Gy^2} $ 대신 $ |Gx| + |Gy| $ 근사식을 사용하여 연산 속도를 높이고 자원을 절약했습니다.
    *   **Look-Up Table (LUT)**: 복잡한 임계값 연산이나 색상 변환 일부를 LUT로 대체하여 처리 속도를 향상시켰습니다.

## 5. 검증 및 결과 (Verification & Results)

### Simulation (ModelSim)
*   **Testbench**: `tb_digital_cam.v`를 통해 전체 시스템을 시뮬레이션하고, 각 단계별 출력(Sobel, Canny 등)을 파일로 덤프하여 검증했습니다.
*   **Python Verification**: 덤프된 Hex 데이터를 Python 스크립트(`hex2img.py`)로 이미지로 변환하여 알고리즘의 정확성을 시각적으로 확인했습니다.

### Hardware Validation
*   **FPGA Implementation**: Quartus Prime을 통해 합성 및 P&R(Place and Route)을 수행하고, Timing Analysis를 통해 셋업/홀드 타임 위반이 없음을 확인했습니다.
*   **Real-Time Demo**: 실제 하드웨어에서 IR 리모컨으로 모드를 전환하며 60fps의 부드러운 영상 처리를 시연했습니다.

## 6. 결론 (Conclusion)
본 프로젝트를 통해 하드웨어 수준에서의 영상 처리 파이프라인 설계 능력과 Verilog HDL을 이용한 복잡한 알고리즘 구현 능력을 입증했습니다. 특히, 제한된 하드웨어 자원 내에서 성능을 최적화하고, CDC 및 타이밍 이슈를 해결하는 과정에서 깊이 있는 디지털 시스템 설계 역량을 갖추게 되었습니다.
