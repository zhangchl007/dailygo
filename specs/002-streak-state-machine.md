# SDD Spec 002: Streak State Machine (连胜状态机与规则)

## 1. Principles
- **Timezone Awareness**: Streaks must be evaluated against the user's localized calendar date.
- **Midnight Grace Period**: A configurable grace period (default: 03:00 local time) allows check-ins recorded between 00:00 and 03:00 to count towards the previous calendar day if the user was active past midnight and has not checked in for that day.
- **Streak Shields (Rest-Day / Freeze Shields)**:
  - Users earn 1 shield every 7 continuous days of streak (capped at 3 shields).
  - If a user misses an active required day, an available shield is automatically consumed to maintain the streak.
  - If no shield is available, the streak resets to 1 (upon new check-in) or 0 (if pending).

## 2. Invariants & Calculation Rules
Let $D_1, D_2, \dots, D_n$ be distinct ordered check-in calendar dates.
1. Duplicate check-ins on the same local calendar day $D_k$ do not increment the streak more than once.
2. For consecutive required days:
   $$\text{gap} = \text{days\_between}(D_{k-1}, D_k)$$
   - If $\text{gap} = 1$: continuous streak ($S_k = S_{k-1} + 1$).
   - If $\text{gap} = 2$ and shields $> 0$: consume 1 shield, $S_k = S_{k-1} + 1$.
   - If $\text{gap} > 1$ and insufficient shields: streak resets to 1.
