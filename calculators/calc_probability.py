import math

def calculate_intervals_for_50_percent_success():
    """
    Calculate intervals needed for 50% chance of success with increasing probability.
    Starting at 1%, increasing by 0.2% each failure.
    """
    base_prob = 0.01  # 1%
    increment = 0.002  # 0.2%
    
    cumulative_failure_prob = 1.0  # Start with 100% chance of no success yet
    interval = 0
    
    while cumulative_failure_prob > 0.5:  # Continue until < 50% chance of no success
        interval += 1
        current_prob = base_prob + (interval - 1) * increment
        
        # Probability of failure this attempt
        failure_prob = 1 - current_prob
        
        # Update cumulative probability of no success yet
        cumulative_failure_prob *= failure_prob
        
        # Success probability so far
        success_prob = 1 - cumulative_failure_prob
        
        if interval <= 20 or interval % 10 == 0:  # Show first 20 and every 10th after
            print(f"Interval {interval}: prob={current_prob:.1%}, cumulative_success={success_prob:.1%}")
    
    print(f"\n50% chance of success reached at interval {interval}")
    return interval

if __name__ == "__main__":
    result = calculate_intervals_for_50_percent_success()