# Repository Guidelines

## Project Structure & Module Organization
Synthesizable RTL lives at the repository root; key entry points are `digital_cam_top.v`, `ov7670_controller.v`, and the three-stage filter cores (`gaussian_3x3_gray8.v`, `sobel_3x3_gray8.v`, `canny_3x3_gray8.v`). Support IP such as `frame_buffer_ram*.v` and `my_altpll*.v` sits beside them so Quartus include paths stay flat. Generated hardware state (`db/`, `incremental_db/`, `output_files/`) belongs in local builds only, while precompiled simulation payloads land in `icarus/` (`*.vvp`) and `simulation/questa/`.

## Build, Test, and Development Commands
Run full synthesis with `quartus_sh --flow compile cam`, or reuse netlists via `quartus_sh --flow assemble cam`; both commands assume you start in the repo root and deposit results under `output_files/`. Refresh an Icarus target with `iverilog -g2012 -o icarus/ov7670_controller.vvp ov7670_controller.v` and execute it using `vvp icarus/ov7670_controller.vvp`. ModelSim or Questa users can import `simulation/questa/cam.vo` and reuse a DO script such as `vsim -do load_cam.do` after adjusting library paths.

## Coding Style & Naming Conventions
Favor Verilog-2001 constructs, four-space indents, and grouped port declarations, mirroring `ov7670_controller.v`. Constants and parameters use `ALL_CAPS`; registers, wires, and generate blocks use `snake_case`. Cluster pipeline stages with brief header comments so pixel-processing order stays obvious, and comment any asynchronous reset logic that deviates from active-low defaults.

## Testing Guidelines
Store behavioral benches next to their targets using the `*_tb.v` suffix so automation can glob them. Benches should self-check and finish with `$finish` to keep CI or batch runs short. House reusable pixel vectors inside `simulation/vectors/` (create when needed) and describe the capture context in the bench header. After touching capture timing, rerun both `vvp icarus/ov7670_capture.vvp` and your preferred Questa script to validate sync and color alignment.

## Commit & Pull Request Guidelines
History shows short, verb-led messages (many bilingual) such as `Tweak sobel porch timing`; follow that style and mention impacted modules. Note regenerated vendor outputs explicitly so reviewers can ignore them. Pull requests should summarize functional impact, cite tested tool versions, and include key screenshots or waveform snippets whenever image quality or timing behavior changes.

## Simulation & Debug Tips
Refresh the `diagram _ Mermaid Chart-*.png` schematics when major bus routing or filter ordering changes. When investigating HSV issues, drive both `background_subtraction.v` and `color_tracker.v` from an identical captured frame to spot mismatched scaling. Keep bulky `.rpt` or `.sft` logs out of commits unless they document a timing regression; if so, quote the slack delta inside the pull-request notes.



1. 당신은 사용자의 어떤 질문이나 아이디어, 정보를 받으면, 아래 사고법 중에 가장 적합한 방식을 두개를 선택하여 혼합하여 분석하세요(1500자 이상)

2. 분석을 토대로 천재적 아이디어를 10개 이상 3000자 이상 출력합니다

아래 공식들은 참고하세요.

---

## 1. 천재적 통찰 도출 공식 (Genius Insight Formula)

GI = (O × C × P × S) / (A + B)

- GI(Genius Insight) = 천재적 통찰
- O(Observation) = 관찰의 깊이 (1-10점)
- C(Connection) = 연결의 독창성 (1-10점)  
- P(Pattern) = 패턴 인식 능력 (1-10점)
- S(Synthesis) = 종합적 사고 (1-10점)
- A(Assumption) = 고정관념 수준 (1-10점)
- B(Bias) = 편향 정도 (1-10점)

적용법: 주제에 대해 각 요소의 점수를 매기고, 고정관념과 편향을 최소화하면서 관찰-연결-패턴-종합의 순서로 사고를 전개하세요.

---

## 2. 다차원적 분석 프레임워크

MDA = Σ[Di × Wi × Ii] (i=1 to n)

- MDA(Multi-Dimensional Analysis) = 다차원 분석 결과
- Di(Dimension i) = i번째 차원에서의 통찰
- Wi(Weight i) = i번째 차원의 가중치
- Ii(Impact i) = i번째 차원의 영향력

분석 차원 설정:
- D1 = 시간적 차원 (과거-현재-미래)
- D2 = 공간적 차원 (로컬-글로벌-우주적)
- D3 = 추상적 차원 (구체-중간-추상)
- D4 = 인과적 차원 (원인-과정-결과)
- D5 = 계층적 차원 (미시-중간-거시)

---

## 3. 창의적 연결 매트릭스

CC = |A ∩ B| + |A ⊕ B| + f(A→B)

- CC(Creative Connection) = 창의적 연결 지수
- A ∩ B = 두 개념의 공통 요소
- A ⊕ B = 배타적 차이 요소
- f(A→B) = A에서 B로의 전이 함수

연결 탐색 프로세스:
1. 직접적 연결 찾기
2. 간접적 연결 탐색
3. 역설적 연결 발견
4. 메타포적 연결 구성
5. 시스템적 연결 분석

---

## 4. 문제 재정의 알고리즘

PR = P₀ × T(θ) × S(φ) × M(ψ)

- PR(Problem Redefinition) = 재정의된 문제
- P₀ = 원래 문제
- T(θ) = θ각도만큼 관점 회전
- S(φ) = φ비율로 범위 조정
- M(ψ) = ψ차원으로 메타 레벨 이동

재정의 기법:
- 반대 관점에서 보기 (θ = 180°)
- 확대/축소하여 보기 (φ = 0.1x ~ 10x)
- 상위/하위 개념으로 이동 (ψ = ±1,±2,±3)
- 다른 도메인으로 전환
- 시간 축 변경

---

## 5. 혁신적 솔루션 생성 공식

IS = Σ[Ci × Ni × Fi × Vi] / Ri

- IS(Innovative Solution) = 혁신적 솔루션
- Ci(Combination i) = i번째 조합 방식
- Ni(Novelty i) = 참신성 지수
- Fi(Feasibility i) = 실현 가능성
- Vi(Value i) = 가치 창출 정도
- Ri(Risk i) = 위험 요소

솔루션 생성 방법:
- 기존 요소들의 새로운 조합
- 전혀 다른 분야의 솔루션 차용
- 제약 조건을 오히려 활용
- 역방향 사고로 접근
- 시스템 전체 재설계

---

## 6. 인사이트 증폭 공식

IA = I₀ × (1 + r)ⁿ × C × Q

- IA(Insight Amplification) = 증폭된 인사이트
- I₀ = 초기 인사이트
- r = 반복 개선율
- n = 반복 횟수
- C = 협력 효과 (1-3배수)
- Q = 질문의 질 (1-5배수)

증폭 전략:
- 'Why'를 5번 이상 반복
- 'What if' 시나리오 구성
- 'How might we' 질문 생성
- 다양한 관점자와 토론
- 아날로그 사례 탐구

---

## 7. 사고의 진화 방정식

TE = T₀ + ∫[L(t) + E(t) + R(t)]dt

- TE(Thinking Evolution) = 진화된 사고
- T₀ = 초기 사고 상태
- L(t) = 시간 t에서의 학습 함수
- E(t) = 경험 축적 함수
- R(t) = 반성적 사고 함수

진화 촉진 요인:
- 지속적 학습과 정보 습득
- 다양한 경험과 실험
- 깊은 반성과 메타인지
- 타인과의 지적 교류
- 실패로부터의 학습

---

## 8. 복잡성 해결 매트릭스

CS = det|M| × Σ[Si/Ci] × ∏[Ii]

- CS(Complexity Solution) = 복잡성 해결책
- det|M| = 시스템 매트릭스의 행렬식
- Si = i번째 하위 시스템 해결책
- Ci = i번째 하위 시스템 복잡도
- Ii = 상호작용 계수

복잡성 분해 전략:
- 시스템을 하위 구성요소로 분해
- 각 구성요소 간 관계 매핑
- 핵심 레버리지 포인트 식별
- 순차적/병렬적 해결 순서 결정
- 전체 시스템 최적화

---

## 9. 직관적 도약 공식

IL = (S × E × T) / (L × R)

- IL(Intuitive Leap) = 직관적 도약
- S(Silence) = 정적 사고 시간
- E(Experience) = 관련 경험 축적
- T(Trust) = 직관에 대한 신뢰
- L(Logic) = 논리적 제약
- R(Rationalization) = 과도한 합리화

직관 활성화 방법:
- 의식적 사고 중단
- 몸과 마음의 이완
- 무의식적 연결 허용
- 첫 번째 떠오르는 아이디어 포착
- 판단 없이 수용

---

## 10. 통합적 지혜 공식

IW = (K + U + W + C + A) × H × E

- IW(Integrated Wisdom) = 통합적 지혜
- K(Knowledge) = 지식의 폭과 깊이
- U(Understanding) = 이해의 수준
- W(Wisdom) = 지혜의 깊이
- C(Compassion) = 공감과 연민
- A(Action) = 실행 능력
- H(Humility) = 겸손함
- E(Ethics) = 윤리적 기준

---

## 사용 가이드라인

1. 단계적 적용: 각 공식을 순차적으로 적용하여 사고를 심화시키세요.

2. 반복적 개선: 한 번의 적용으로 끝내지 말고 여러 번 반복하여 정교화하세요.

3. 다양한 관점: 서로 다른 배경을 가진 사람들과 함께 공식을 적용해보세요.

4. 실험적 태도: 공식을 기계적으로 따르기보다는 창의적으로 변형하여 사용하세요.

5. 균형적 접근: 분석적 사고와 직관적 사고를 균형 있게 활용하세요.

---

## 2025년 10월 10일 - Gemini

### 작업 요약
- **배경 제거 기능 개선 및 컬러 트래킹 기능 확장**

### 상세 작업 내역

#### 1. 배경 제거 알고리즘 개선 (휘도(Luminance) 기반으로 전환)
- **문제점**: 기존 RGB 채널 차이 합산 방식은 영상의 밝기에 따라 민감도가 달라지는 문제 발생 (밝은 곳에서 과민 반응, 어두운 곳에서 둔감).
- **1차 해결**: `adaptive_background.v` 모듈을 수정하여, 전경/배경 판단 기준을 RGB 값에서 8비트 그레이스케일(휘도) 값의 차이로 변경.
    - `rgb_to_gray` 함수 추가.
    - `digital_cam_top.v`의 관련 임계값(`bg_sub_threshold_btn`) 초기치를 `160`에서 `40`으로, 최대치를 `255`로 조정하여 안정성 향상.
- **2차 문제 제기**: 사용자가 흰색과 같은 매우 밝은 영역은 여전히 오작동 가능성을 제기함.
- **근본 해결책 제안**: `GEMINI.md`에 분석된 **동적 임계값(Dynamic Threshold)** 방식을 최종 해결책으로 제안. (배경의 밝기에 따라 임계값을 실시간으로 변경하여 밝은 영역의 노이즈를 효과적으로 제거하는 방식)

#### 2. 파이프라인 타이밍 버그 수정
- **문제점**: 사용자가 `adaptive_fg_flag_delayed` 신호의 잠재적 오류를 지적. 분석 결과, `adaptive_background` 모듈의 내부 지연(4클럭)이 고려되지 않아 움직임 감지 마스크가 원본 영상과 4클럭만큼 어긋나는 **타이밍 정렬 오류** 확인.
- **해결**: `digital_cam_top.v`에서 최종 출력단을 `adaptive_fg_flag_delayed[IDX_ORIG - 4]`로 수정하여 지연 시간을 보상하고 타이밍을 정확히 맞춤.

#### 3. 사용자 인터페이스(UI) 및 기능 추가
- **배경색 변경**: 배경 제거 모드에서 배경을 표시하는 색상을 검은색에서 **초록색**으로 변경.
- **컬러 트래킹 기능 확장**:
    - IR 리모컨 `0x01`(빨강), `0x02`(초록), `0x03`(파랑) 키로 특정 색상을 추적하는 필터 기능 추가 요청.
    - `color_tracker.v` 모듈을 수정하여 외부에서 `color_select` 입력으로 추적할 색상을 선택할 수 있도록 재설계.
    - `digital_cam_top.v`에 관련 IR 코드 및 제어 레지스터(`color_track_select`) 추가. (현재 수정 진행 중)

### 프로젝트 상태 및 다음 단계
- 배경 제거 기능의 1차 개선 및 치명적인 타이밍 버그 수정 완료.
- 컬러 트래킹 기능 확장을 위한 하위 모듈(`color_tracker.v`) 수정 완료.
- **다음 단계**: `digital_cam_top.v`의 IR 리모컨 제어 로직과 `color_tracker` 모듈 연결을 완료하여 기능 확장을 마무리할 예정.
