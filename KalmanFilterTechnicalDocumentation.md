# Kalman Filter Technical Documentation
## For Beginners in Control Theory

This document explains the Kalman filter implementation in simple terms, assuming minimal background in control theory.

---

## Table of Contents
1. [What Problem Are We Solving?](#what-problem-are-we-solving)
2. [What is a Kalman Filter?](#what-is-a-kalman-filter)
3. [The Two Steps: Predict and Update](#the-two-steps-predict-and-update)
4. [Understanding the Math (Simple Explanation)](#understanding-the-math-simple-explanation)
5. [Key Parameters: Q, R, and P](#key-parameters-q-r-and-p)
6. [Why Kalman Filter Works Better Than Simple Methods](#why-kalman-filter-works-better-than-simple-methods)
7. [Step-by-Step Through Our Implementation](#step-by-step-through-our-implementation)

---

## What Problem Are We Solving?

### The Challenge: Estimating Battery State of Charge (SOC)

Imagine you're driving an electric vehicle. You want to know:
- **How much charge is left?** (SOC = 0% to 100%)
- **How far can I drive?**

**The Problem:**
- You **cannot directly measure** SOC (like you can't "see" charge inside a battery)
- You **can measure**: voltage, current, temperature
- These measurements are **noisy** (not perfectly accurate)
- The battery's behavior changes with temperature, age, and usage

**Our Solution:**
- Use a Kalman filter to **estimate** SOC by combining:
  - **What we expect** (based on physics: current integration)
  - **What we observe** (voltage measurements)

---

## What is a Kalman Filter?

### Simple Analogy: The GPS Navigation Problem

Think of estimating SOC like GPS navigation in a car:

1. **Dead Reckoning** (like Coulomb counting):
   - Start at a known location
   - Track speed and direction over time
   - Estimate current position
   - **Problem**: Small errors accumulate over time → you drift off course

2. **GPS Only** (like using voltage measurements alone):
   - Trust GPS signal completely
   - **Problem**: GPS has noise and can be temporarily wrong
   - **Problem**: Voltage doesn't directly tell you SOC (depends on current too)

3. **Kalman Filter** (combines both):
   - Use dead reckoning to predict position
   - Use GPS to correct the prediction
   - **Weigh each source** based on how reliable it is
   - **Result**: More accurate than either alone!

### The Core Idea

A Kalman filter is a **smart way to combine**:
- **Process model** (what we expect based on physics)
- **Measurements** (what we actually observe)

It automatically decides:
- **When to trust** the physics model more
- **When to trust** the measurements more
- Based on how **uncertain** each source is

---

## The Two Steps: Predict and Update

Every time we get a new measurement, the Kalman filter does two things:

### Step 1: PREDICT (Time Update)

**What we do:**
- Use our **current SOC estimate** and **current measurements** (current)
- Predict what SOC **should be** at the next time step
- Increase our **uncertainty** (because prediction isn't perfect)

**In our code:**
```matlab
% Predict next SOC using current integration
x_pred = x - (I_cell(k) * dt_k) / Q_C;
P_pred = P + Q;  % Uncertainty increases
```

**Why uncertainty increases?**
- Small errors in current measurement accumulate
- Battery capacity might change slightly
- Temperature effects aren't perfectly modeled
- **Metaphor**: Like a ship's position uncertainty growing as you travel without GPS

### Step 2: UPDATE (Measurement Update)

**What we do:**
- Compare our **prediction** with the **actual voltage measurement**
- Calculate a **correction factor** (Kalman gain)
- Blend prediction and measurement (weighted by their reliability)
- Decrease our **uncertainty** (because we got new information)

**In our code:**
```matlab
% Calculate correction based on voltage
residual = V_measured - V_pred;
K = P_pred * H' / S;  % Kalman gain
x = x_pred + K * residual;  % Update estimate
P = (1 - K * H) * P_pred;  % Uncertainty decreases
```

**Why uncertainty decreases?**
- We got new information (voltage measurement)
- This helps "pin down" our estimate
- **Metaphor**: Like GPS signal reducing navigation uncertainty

---

## Understanding the Math (Simple Explanation)

### The State: What We're Estimating

**State = SOC** (State of Charge)

- This is the **single number** we're trying to figure out
- Ranges from 0 (empty) to 1 (full)
- Cannot be directly measured

### The Process Model: Physics Prediction

**How SOC Changes:**
```
SOC(t+1) = SOC(t) - (Current × Time) / Capacity
```

**Translation:**
- If current flows **out** (positive), SOC **decreases**
- If current flows **in** (negative/charging), SOC **increases**
- Change depends on **how long** current flows and **battery capacity**

**This is the same as Coulomb counting!**

**Example:**
- Current = 10 A (discharging)
- Time = 1 hour = 3600 seconds
- Capacity = 27 Ah = 97,200 Coulombs
- Change in SOC = (10 × 3600) / 97,200 = 0.37 (37%)

### The Measurement Model: Voltage Relationship

**How Voltage Relates to SOC:**
```
Voltage = OCV(SOC) - Current × Resistance
```

Where:
- **OCV(SOC)** = Open Circuit Voltage (depends on SOC)
  - Higher SOC → Higher OCV
  - Looked up from a table
- **Current × Resistance** = Voltage drop due to current flow

**Key Point:** Voltage is not directly SOC, but it's related!

### The Predict Step (Detailed)

```matlab
% Step 1: Predict next SOC
x_pred = x - (I_cell(k) * dt_k) / Q_C;

% Step 2: Increase uncertainty
P_pred = P + Q;
```

**What's happening:**
1. Take current SOC estimate (`x`)
2. Subtract charge removed/added (current × time / capacity)
3. This gives predicted SOC (`x_pred`)
4. Uncertainty (`P`) increases by process noise (`Q`)

**Why uncertainty increases?**
- Current measurement has small errors
- Battery capacity might vary slightly
- We're not accounting for temperature, aging, etc.
- `Q` quantifies how much uncertainty to add

### The Update Step (Detailed)

```matlab
% Step 1: Predict voltage based on predicted SOC
OCV_pred = OCVf(x_pred);
V_pred = OCV_pred - I_cell(k) * R_ohm;

% Step 2: Compare with actual voltage
residual = V_measured - V_pred;

% Step 3: Calculate Kalman gain
H = dOCV_dSOC;  % How much voltage changes per unit SOC
S = H * P_pred * H' + R;  % Total uncertainty
K = P_pred * H' / S;  % How much to trust measurement

% Step 4: Update SOC estimate
x = x_pred + K * residual;

% Step 5: Update uncertainty
P = (1 - K * H) * P_pred;
```

**Step-by-step explanation:**

1. **Predict voltage:**
   - Based on predicted SOC, what voltage should we see?
   - `V_pred = OCV(SOC_predicted) - I × R`

2. **Calculate residual (error):**
   - `residual = V_actual - V_predicted`
   - If residual is large → our prediction was wrong
   - If residual is small → our prediction was good

3. **Calculate Kalman gain (`K`):**
   - This tells us **how much to correct** our prediction
   - If `K` is large (close to 1) → trust measurement a lot
   - If `K` is small (close to 0) → trust prediction more
   - Formula: `K = (Our Uncertainty) / (Total Uncertainty)`

4. **Update SOC estimate:**
   - `x_new = x_predicted + K × residual`
   - This **blends** prediction and measurement
   - If `K = 0.5`: 50% prediction, 50% measurement correction

5. **Update uncertainty:**
   - Getting a measurement **reduces** our uncertainty
   - `P_new = (1 - K) × P_predicted`

### Example Calculation

**Starting point:**
- SOC estimate: `x = 0.8` (80%)
- Uncertainty: `P = 0.01`
- Current: `I = 10 A` (discharging)
- Time step: `dt = 1 s`
- Capacity: `Q_C = 97,200 C`

**PREDICT STEP:**
1. Predict SOC: `x_pred = 0.8 - (10 × 1) / 97,200 = 0.7999`
2. Increase uncertainty: `P_pred = 0.01 + 1e-5 = 0.01001`

**UPDATE STEP:**
1. Predict voltage: `V_pred = OCV(0.7999) - 10 × 0.011 = 3.71 - 0.11 = 3.60 V`
2. Measure voltage: `V_measured = 3.58 V`
3. Residual: `residual = 3.58 - 3.60 = -0.02 V` (voltage lower than expected)
4. Calculate gain: `K = 0.01001 × H / (H² × 0.01001 + 0.1) ≈ 0.09`
5. Update SOC: `x = 0.7999 + 0.09 × (-0.02 / H) ≈ 0.7995` (slight correction downward)
6. Reduce uncertainty: `P = (1 - 0.09 × H) × 0.01001 ≈ 0.0095`

**Interpretation:**
- Voltage was slightly lower than expected
- This suggests SOC might be a bit lower
- Small correction applied (gain was small, so we trust prediction more)

---

## Key Parameters: Q, R, and P

### P: State Uncertainty (Covariance)

**What it is:**
- How **uncertain** we are about our SOC estimate
- Low P = we're confident in our estimate
- High P = we're not sure

**How it changes:**
- **Increases** during predict step (prediction adds uncertainty)
- **Decreases** during update step (measurement reduces uncertainty)

**Example:**
- `P = 0.01` means uncertainty of ~10% (√0.01 ≈ 0.1)
- `P = 0.0001` means uncertainty of ~1% (√0.0001 = 0.01)

### Q: Process Noise (Process Covariance)

**What it is:**
- How much **uncertainty** the physics model adds each time step
- Represents: measurement errors, model imperfections, unmodeled effects

**If Q is small:**
- Trust the physics model (Coulomb counting) a lot
- Measurement corrections are small
- **Result:** Behaves more like pure Coulomb counting

**If Q is large:**
- Don't trust the physics model as much
- Measurements have more influence
- **Result:** More reactive to voltage measurements

**In our code:**
```matlab
Q = 1e-5;  % Small value = trust process model
```

### R: Measurement Noise (Measurement Covariance)

**What it is:**
- How much **uncertainty** we have in voltage measurements
- Represents: sensor noise, temperature effects, battery variations

**If R is small:**
- Trust voltage measurements a lot
- Large corrections when voltage doesn't match prediction
- **Result:** More sensitive to voltage

**If R is large:**
- Don't trust voltage measurements as much
- Smaller corrections
- **Result:** More like pure Coulomb counting

**In our code:**
```matlab
R = 0.1;  % Medium value = moderate trust in voltage
```

### Tuning Q and R

**The Art:**
- If SOC drifts over time → increase Q (or decrease R)
- If SOC is too jumpy → decrease Q (or increase R)
- If voltage measurements are noisy → increase R

**Typical Values:**
- Q: `1e-6` to `1e-4` (very small, trust physics)
- R: `0.01` to `1.0` (depends on voltage sensor quality)

---

## Why Kalman Filter Works Better Than Simple Methods

### Method 1: Pure Coulomb Counting

**How it works:**
- Start with known SOC
- Integrate current over time
- `SOC(t) = SOC(0) - ∫(Current) dt / Capacity`

**Problems:**
- Small errors in current measurement accumulate
- No correction for drift
- Doesn't use voltage information

**Result:** Accurate short-term, but drifts over time

### Method 2: Pure Voltage Lookup

**How it works:**
- Measure voltage
- Look up SOC from voltage table
- Ignore current history

**Problems:**
- Voltage depends on current (voltage drop)
- Temperature affects voltage
- No memory of past state

**Result:** Can be inaccurate during current flow

### Method 3: Kalman Filter (Combined)

**How it works:**
- Use Coulomb counting for prediction
- Use voltage for correction
- Weight each by uncertainty

**Advantages:**
- Corrects for current measurement errors
- Uses voltage to prevent drift
- Adapts based on confidence levels
- Best of both worlds!

**Result:** More accurate and robust than either alone

---

## Step-by-Step Through Our Implementation

### Initialization

```matlab
% Initial SOC estimate from voltage
[~, idx0] = min(abs(OCV_vec - V_cell(1)));
SOC0 = SOC_vec(idx0);

% Kalman filter initial state
x = SOC0;        % Start with voltage-based estimate
P = 0.01;        % Initial uncertainty (moderate)
Q = 1e-5;        % Process noise (small = trust physics)
R = 0.1;         % Measurement noise (moderate)
```

**What's happening:**
- Estimate initial SOC from first voltage measurement
- Set moderate initial uncertainty
- Set small Q (trust Coulomb counting)
- Set moderate R (trust voltage but not completely)

### Main Loop (For Each Time Step)

#### 1. Predict Step

```matlab
% Predict next SOC using physics
x_pred = x - (I_cell(k) * dt_k) / Q_C;
x_pred = max(0, min(1, x_pred));  % Clamp to valid range

% Increase uncertainty
P_pred = P + Q;
```

**What's happening:**
- Use current integration to predict next SOC
- Add process noise to uncertainty
- Clamp SOC to [0, 1] range

#### 2. Compute Expected Voltage

```matlab
OCV_pred = OCVf(x_pred);
V_pred = OCV_pred - I_cell(k) * R_ohm;
```

**What's happening:**
- Look up OCV for predicted SOC
- Account for voltage drop due to current
- This is what voltage "should be"

#### 3. Calculate Measurement Sensitivity

```matlab
eps = 1e-6;
OCV_plus = OCVf(x_pred + eps);
dOCV_dSOC = (OCV_plus - OCV_pred) / eps;
H = dOCV_dSOC;
```

**What's happening:**
- Calculate how much voltage changes when SOC changes
- This is the "Jacobian" (sensitivity)
- Used to convert voltage error into SOC correction

#### 4. Compute Kalman Gain

```matlab
S = H * P_pred * H' + R;
K = P_pred * H' / S;
```

**What's happening:**
- `S` = total uncertainty in voltage prediction
- `K` = how much to trust the measurement
- If `P_pred` is large → large K (trust measurement more)
- If `R` is large → small K (trust measurement less)

#### 5. Update State

```matlab
residual = V_measured - V_pred;
x = x_pred + K * residual / H;  % Convert voltage error to SOC correction
x = max(0, min(1, x));
```

**What's happening:**
- Calculate voltage prediction error
- Convert to SOC correction using gain and sensitivity
- Blend prediction and measurement

#### 6. Update Uncertainty

```matlab
P = (1 - K * H) * P_pred;
```

**What's happening:**
- Uncertainty decreases because we got new information
- Amount of decrease depends on gain K

---

## Key Insights

### 1. The Gain Controls Everything

- **High gain (K ≈ 1):**
  - Trust measurements a lot
  - Large corrections
  - More responsive
  - Can be jumpy if measurements are noisy

- **Low gain (K ≈ 0):**
  - Trust physics model more
  - Small corrections
  - More stable
  - Can drift if model is wrong

### 2. Uncertainty Tracks Confidence

- **Low uncertainty (P small):**
  - We're confident in estimate
  - Corrections are small
  - Stable estimate

- **High uncertainty (P large):**
  - We're not confident
  - Corrections are large
  - Estimate can change quickly

### 3. The Filter is Self-Correcting

- If prediction is wrong → residual is large → large correction
- If measurements are noisy → R is large → small corrections
- If model is good → Q is small → trust predictions more

---

## Common Questions

### Q: Why not just use Coulomb counting?

**A:** Coulomb counting accumulates errors over time. The Kalman filter uses voltage to correct these errors.

### Q: Why not just use voltage lookup?

**A:** Voltage depends on current (voltage drop) and temperature. The Kalman filter accounts for current and uses Coulomb counting to track history.

### Q: How do I choose Q and R?

**A:** 
- Start with small Q (1e-5) and medium R (0.1)
- If estimate drifts → increase Q or decrease R
- If estimate is jumpy → decrease Q or increase R
- Tune by comparing to known ground truth (like Coulomb counting)

### Q: What if measurements are missing?

**A:** Skip the update step, just do predict. Uncertainty will grow until next measurement.

### Q: Can I add more states (like temperature)?

**A:** Yes! Extend state vector to `[SOC; Temperature]` and update process/measurement models accordingly.

---

## Summary

The Kalman filter is a **smart way to combine**:
- **Physics model** (Coulomb counting) → predicts what SOC should be
- **Measurements** (voltage) → corrects the prediction

**Key advantages:**
- Automatically weights each source by reliability
- Tracks uncertainty and confidence
- Self-correcting
- More accurate than either method alone

**The two-step process:**
1. **Predict:** Use physics to guess next state (uncertainty increases)
2. **Update:** Use measurement to correct guess (uncertainty decreases)

**The result:** Better SOC estimates than simple methods!

---

*End of Technical Documentation*


