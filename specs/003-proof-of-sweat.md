# SDD Spec 003: Proof of Sweat Anti-Cheat Engine (汗水防作弊机制)

## 1. Goal
Validate exercise authenticity using multi-sensor evidence without draining battery.

## 2. Multi-Metric Scoring Model
For a workout claiming duration $T$ (minutes) and metric target $M$:
- **Heart Rate Score ($W_{hr} = 0.35$)**:
  - Heart rate exertion ratio $r = \frac{HR_{avg} - HR_{resting}}{HR_{max\_est} - HR_{resting}}$
  - Score = $\min(1.0, \max(0.0, r \times 1.5))$
- **Step / Cadence Score ($W_{cad} = 0.35$)**:
  - Cadence (steps/min) vs expected cadence for activity.
- **Calorie / Energy Consistency ($W_{cal} = 0.30$)**:
  - METs estimated vs reported calorie burn.

## 3. Thresholds
- Overall Score $S = W_{hr} \cdot S_{hr} + W_{cad} \cdot S_{cad} + W_{cal} \cdot S_{cal}$.
- $S \ge 0.70 \implies \text{Verified}$.
- $0.35 \le S < 0.70 \implies \text{SelfReported}$.
- $S < 0.35$ with contradictory data $\implies \text{Suspect}$.
