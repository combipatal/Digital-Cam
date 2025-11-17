# FPGA 기반 실시간 이미지 프로세싱 시스템

## 프로젝트 개요
- OV7670 카메라에서 RGB565 스트림을 읽어 320×240으로 축소 저장 후 VGA 640×480 @ 60Hz로 실시간 출력하는 FPGA 비전 파이프라인입니다.
- `digital_cam_top.v`가 모든 하위 모듈(카메라 제어, 프레임 버퍼, 이미지 필터, VGA 타이밍, IR 리모컨)을 총괄하며, 필터 모드에 따라 다양한 영상 처리를 적용합니다.
- 2025-10-15/16 리팩토링에서 파이프라인 지연 관리, 테스트 경로 노출, 배경제거/컬러트래킹 검증 흐름이 대폭 강화되었습니다. 

## 시스템 아키텍처
1. **카메라 설정 및 캡처**  
   `ov7670_controller.v`가 I2C로 레지스터를 설정하고, `ov7670_capture.v`가 픽셀 클럭(`ov7670_pclk`) 도메인에서 16비트 RGB565 프레임을 생성합니다. 동시에 2×2 평균 필터로 다운스케일링하여 프레임 버퍼에 기록합니다.
2. **프레임 버퍼**  
   `frame_buffer_ram*.v` (듀얼포트 RAM)과 `bg_buffer_ram*`가 각각 실시간 화면과 배경 모델을 저장합니다. VGA 도메인에서는 듀얼 뱅크 구조를 통해 연속 프레임 액세스를 지원합니다.
3. **VGA 타이밍 및 업스케일링**  
   `vga_640.v`가 25.175 MHz 도메인에서 타이밍을 생성하고, 320×240 데이터를 최근접 2× 업스케일링합니다. 모듈 내부에서 2클럭 메모리 지연을 보상하도록 재작성되어 상위 모듈 연결이 단순합니다.
4. **이미지 처리 파이프라인**  
   가우시안 블러(`gaussian_3x3_gray8.v`) → Sobel(`sobel_3x3_gray8.v`) → Canny(`canny_3x3_gray8.v`) 순으로 연결되며, HSV 변환(`rgb_to_hsv.v`)과 `color_tracker.v`, `adaptive_background.v`가 병렬로 동작합니다. 모든 경로는 `PIPE_LATENCY=7` 클럭 기준으로 정렬됩니다.
5. **출력 멀티플렉서**  
   IR 리모컨으로 선택한 `active_filter_mode`에 따라 VGA 신호가 원본·필터·배경제거·컬러트래킹 결과 등으로 전환됩니다.

## 최근 핵심 개선 사항 (요약)
- **파이프라인 동기화 보정:** Sobel/Canny와 같이 자체 지연이 긴 필터에는 추가 지연을 제거하고, 다른 신호는 고유 지연에 맞춰 `PIPE_LATENCY`에 정렬했습니다.
- **레지스터 사용 감소:** RGB888 확장을 최종 단계로 미루어 파이프라인 레지스터 수를 33 % 절감했습니다.
- **Dead Code 정리:** 미사용 동적 임계 로직, `bg_sub_out` 체인, `filter_ready_delayed`, 수동 `..._d1/_d2` 정렬 코드 등을 삭제했습니다.
- **배경 RAM 경고 차단:** Bank2 미사용 시 주소선을 0으로 마스킹하여 ModelSim 경고를 제거했습니다.
- **테스트 경로 확장:** `test_digital_cam_top.v`에서 Sobel/Canny/가우시안/컬러트래커/배경제거 신호를 모두 외부 포트로 노출해 TB에서 직접 덤프할 수 있습니다.
- **자동 배경 캡처 최적화:** VGA 활성화 신호와 반대 위상을 이용해 배경 캡처 신호를 단순화하고, 리셋 후 첫 프레임을 자동 배경으로 사용합니다.

## 이미지 처리 모드 및 테스트 포트
| 모드 | `active_filter_mode` | 내용 | 테스트 결과물 |
| --- | --- | --- | --- |
| `MODE_ORIG` | 3'd0 | 업스케일된 원본 RGB565 | `px_value.hex` |
| `MODE_GRAY` | 3'd1 | Luma 기반 그레이스케일 | 내부 파이프라인 사용 |
| `MODE_SOBEL` | 3'd2 | 소벨 엣지 맵 | `px_value_sobel.hex`, `sobel_value` 포트 |
| `MODE_CANNY` | 3'd3 | 캐니 엣지 맵 | `px_value_canny.hex`, `canny_value` 포트 |
| `MODE_COLOR` | 3'd4 | HSV 기반 컬러 트래킹 | `px_mask_color.hex`, `color_track_mask/ready` |
| `MODE_BG_SUB` | 3'd5 | 적응형 배경제거 | `px_background.hex` |
| `MODE_GAUSS` | 3'd6 | 가우시안 블러 (VGA 및 테스트) | `px_value_gaussian.hex`, `gaussian_value/ready` |

`test_digital_cam_top.v`에서는 `pixel_valid`, `vsync`, `adaptive_fg_mask`, `pixel_rgb565` 등 시뮬레이션 친화적인 포트가 추가되었으며, `tb_digital_cam.v`가 이를 이용해 각 HEX 파일을 생성합니다.

## IR 리모컨 기본 매핑
- `KEY_ORIG (0x12)` : 원본 모드  
- `KEY_BG_MODE (0x04)` : 배경제거 모드  
- `KEY_BG_THR_UP/DOWN (0x1B / 0x1F)` : FG 임계값 ±1  
- `KEY_1/2/3 (0x01/0x02/0x03)` : 컬러트래커 기준색(R/G/B)  
- `KEY_UP / KEY_DOWN (0x1A / 0x1E)` : 기타 파라미터 확장용 (코드 참조)  
필요 시 `digital_cam_top.v` 내 상수들을 수정해 키 매핑을 재설정할 수 있습니다.

## 빌드 & 배포
### Quartus Prime
1. Quartus Prime(예: 20.1 Lite)에서 `cam.qpf`를 열고 **Processing → Start Compilation** 실행.
2. 컴파일 결과물(`output_files/`)을 확인한 뒤 USB-Blaster로 대상 FPGA(예: Cyclone IV, DE0-Nano 등) 보드에 프로그래밍합니다.
3. OV7670 모듈, VGA 커넥터, IR 수신기, 버튼을 핀아웃에 맞춰 연결합니다. (핀맵은 `cam.qsf` 참조)
4. 전원 인가 후 LED(`led_config_finished`)가 켜지면 OV7670 설정이 완료된 상태입니다.

### 시뮬레이션 (ModelSim / Questa)
1. `simulation/` 또는 사용자 환경에 맞는 작업 폴더에서 다음을 로드합니다.
   ```tcl
   vlog ../digital_cam_top.v ../test_digital_cam_top.v ../tb_digital_cam.v <필요 모듈들>
   vsim tb_digital_cam
   ```
2. `tb_digital_cam.v`는 Windows 경로(`C:/git/Verilog-HDL/cam/...`)를 기본값으로 사용하므로, 실제 위치에 맞게 `$readmemh` 경로를 수정하거나 심볼릭 링크를 사용하세요.
3. 시뮬레이션을 한 프레임 이상 진행하면 `px_*.hex`가 생성됩니다. `hex2img.py` 또는 `hex2img16.py`로 BMP/PNG로 변환하여 결과를 확인할 수 있습니다.

### Python 기반 이미지 변환
```bash
bash -lc "python3 hex2img16.py px_background.hex 640 480 out_background.png"
```
필요 시 `img2hex.py`로 실험용 프레임을 생성하여 TB 입력으로 사용할 수 있습니다.

## 디렉터리 개요
- `digital_cam_top.v` : 상위 파이프라인 및 필터/IR 제어.
- `ov7670_controller.v`, `ov7670_capture.v` : 카메라 설정 및 데이터 캡처.
- `vga_640.v` : VGA 타이밍/업스케일 엔진.
- `gaussian_3x3_gray8.v`, `sobel_3x3_gray8.v`, `canny_3x3_gray8.v` : 핵심 필터 블록.
- `adaptive_background.v`, `color_tracker.v`, `rgb_to_hsv.v` : 배경제거·컬러추적 모듈.
- `test_digital_cam_top.v`, `tb_digital_cam.v` : 시뮬레이션 상위/테스트벤치.
- `hex2img*.py`, `img2hex.py` : HEX ↔ 이미지 변환 스크립트.
- `AGENTS.md` : 최신 리팩토링 기록 및 모듈 설명.

## 참고 및 향후 작업
- 하드웨어 실험 시 OV7670 라인 타이밍과 VGA 동기화를 반드시 오실로스코프로 확인하세요.
- 새로운 필터를 추가할 경우 해당 경로의 파이프라인 지연을 `PIPE_LATENCY`에 맞춰 보정해야 합니다.

