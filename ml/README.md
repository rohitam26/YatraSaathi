# YatraSaathi — ML Arrival Confidence System

## 1. Objective and Architecture

The Machine Learning Arrival Confidence subsystem predicts the probability (\(0.0 \dots 1.0\)) that a traveler has genuinely arrived and come to a halt at a scheduled stop, rather than merely passing through at high transit speed, experiencing a transient GPS drift spike, or reading a stale cached coordinate.

### Safety Guarantee: Deterministic First Architecture
- **Safety Gate:** The deterministic rule-based `ArrivalDetector` (Haversine distance within radius, minimum 3 consecutive samples, minimum 10-second dwell time, max 50m accuracy error, max 45s sample age) remains the **authoritative primary gate**.
- **Assistive ML Role:** The ML confidence score acts as a secondary verification and transparent user feedback gauge. It **never** triggers an alert on its own if deterministic boundary checks fail.
- **Zero Cloud & Zero External APIs:** The trained model parameters are embedded directly into the offline Flutter app runtime (`lib/services/arrival_confidence_ml.dart`), ensuring zero network requests, zero external latency, and complete user privacy.

---

## 2. Input Features

The model evaluates 8 kinematic and geospatial telemetry features extracted from the ongoing GPS stream:

| Feature Name | Description | Normalization Range | Learned Weight | Interpretation |
| :--- | :--- | :--- | :--- | :--- |
| `distance_ratio` | Current distance to stop / Stop radius | \([0.0, 2.0]\) | \(-1.6840\) | Negative: High distance strongly indicates user is not at stop |
| `accuracy_score` | GPS horizontal accuracy error | \([0.0, 1.0]\) (1.0 = \(\le 0\text{m}\), 0.0 = \(\ge 100\text{m}\)) | \(+0.0351\) | Positive: Tight GPS fix increases confidence |
| `freshness_score` | Temporal age of GPS sample | \([0.0, 1.0]\) (1.0 = \(\le 5\text{s}\), 0.0 = \(\ge 60\text{s}\)) | \(+0.2989\) | Positive: Real-time fixes increase confidence |
| `speed_score` | Vehicle instantaneous speed | \([0.0, 1.0]\) (1.0 = \(\ge 30\text{ m/s}\), 0.0 = \(0\text{ m/s}\)) | \(-1.6463\) | Negative: High transit speed indicates vehicle has not stopped |
| `consecutive_samples_ratio`| Consecutive valid samples within radius / 3 | \([0.0, 1.0]\) | \(+1.5049\) | Positive: Repeated observations confirm presence |
| `dwell_ratio` | Time elapsed inside stop radius / 10s | \([0.0, 1.0]\) | \(+2.7258\) | Positive: Strongest positive signal of actual stop arrival |
| `speed_stability` | Inverse variance of speed over recent window | \([0.0, 1.0]\) | \(+0.6185\) | Positive: Deceleration or stationary state |
| `convergence_rate` | Rate of distance decrease towards stop center | \([0.0, 1.0]\) | \(-1.3870\) | Negative: Still approaching stop at speed |
| **Bias** | Baseline intercept | — | \(-1.2459\) | Conservative prior: assumes non-arrival until evidence mounts |

---

## 3. Training & Evaluation Pipeline

The training pipeline is implemented in `ml/train_arrival_model.py`.

- **Dataset Size:** 5,000 synthetic transit trajectory samples across 5 scenarios:
  1. *True Arrival:* Decelerating, low speed (\(<3.5\text{ m/s}\)), sustained dwell (\(>10\text{s}\)), high accuracy.
  2. *Express Fly-by:* High speed (\(12 \dots 30\text{ m/s}\)), transit through radius without dwell.
  3. *GPS Drift Spike:* Inaccurate fix (\(\pm 55 \dots 180\text{m}\)), single isolated sample.
  4. *Approaching Far:* Distance ratio \(> 1.2\), approaching stop.
  5. *Stale Fix:* Sample age \(50 \dots 300\text{s}\) cached from previous background wakeups.
- **Split:** Stratified 80% training (4,000 samples) and 20% holdout test (1,000 samples).
- **Optimization:** Regularized Logistic Regression with \(L_2\) regularization (\(\lambda = 0.001\)), learning rate \(\alpha = 0.2\), 250 epochs.
- **Evaluation Metrics (Holdout Test Set):**
  - **Accuracy:** \(100.00\%\)
  - **Precision:** \(100.00\%\)
  - **Recall:** \(100.00\%\)
  - **F1 Score:** \(1.0000\)
  - **Confusion Matrix:**
    - True Positives: 471
    - True Negatives: 529
    - False Positives: 0
    - False Negatives: 0

---

## 4. Mobile Inference Integration

The Flutter app executes the model using `lib/services/arrival_confidence_ml.dart`:
```dart
final confidence = ArrivalConfidenceEstimator.estimateConfidence(
  distanceMeters: distance,
  radiusMeters: stop.radiusMeters,
  accuracyMeters: reading.accuracyMeters,
  sampleAge: reading.age(),
  speedMps: reading.speedMps ?? 0.0,
  consecutiveSamples: consecutiveCount,
  dwellDuration: dwellTime,
);
```

If any telemetry parameter is missing or out of valid bounds, the system automatically falls back to an interpretable **Rule-Based Confidence Estimator** that scores confidence based on distance percentage and dwell progression.

---

## 5. Limitations & Future Real-World Validation

> [!WARNING]
> This model was trained on a mathematically modeled **synthetic dataset** simulating urban transit dynamics. While synthetic data rigorously validates pipeline correctness and numerical stability, it is **not** a substitute for real-world field trials across various transit types (metro, suburban rail, intercity bus, highway auto).
>
> The model is officially labeled **EXPERIMENTAL** within the application UI. The deterministic rule-based arrival detector remains the production-safe decision maker.

