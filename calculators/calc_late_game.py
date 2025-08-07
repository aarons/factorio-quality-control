def calculate_foundry_speed():
    """
    Calculate final speed for Epic Foundry with modules and beacons
    """
    # Base stats
    epic_foundry_speed = 7.6
    
    # Direct modules in foundry: 4x Rare Speed 3 modules
    rare_speed3_bonus = 0.8  # 80% each
    direct_modules = 4
    direct_speed_bonus = direct_modules * rare_speed3_bonus
    
    # Beacon calculation
    num_beacons = 4
    rare_beacon_distribution = 1.9  # rare beacon distribution efficiency
    speed3_modules_per_beacon = 2
    
    # Transmission strength = distribution_efficiency * sqrt(num_beacons)
    transmission_strength = rare_beacon_distribution * (num_beacons ** 0.5)
    
    # Each beacon has 2 speed 3 modules
    beacon_speed_bonus_per_beacon = speed3_modules_per_beacon * rare_speed3_bonus
    total_beacon_speed_bonus = beacon_speed_bonus_per_beacon * transmission_strength
    
    # Final calculation
    total_speed_multiplier = 1 + direct_speed_bonus + total_beacon_speed_bonus
    final_speed = epic_foundry_speed * total_speed_multiplier
    
    print("Epic Foundry Speed Calculation:")
    print(f"Base Epic Foundry speed: {epic_foundry_speed}")
    print(f"Direct modules: {direct_modules}x Rare Speed 3 (+{rare_speed3_bonus*100}% each)")
    print(f"Direct speed bonus: +{direct_speed_bonus*100:.0f}%")
    print()
    print(f"Beacons: {num_beacons}x Rare beacons (distribution {rare_beacon_distribution})")
    print(f"Modules per beacon: {speed3_modules_per_beacon}x Rare Speed 3")
    print(f"Transmission strength: {rare_beacon_distribution} × √{num_beacons} = {transmission_strength:.2f}")
    print(f"Beacon speed bonus per beacon: {beacon_speed_bonus_per_beacon*100:.0f}%")
    print(f"Total beacon speed bonus: {total_beacon_speed_bonus*100:.1f}%")
    print()
    print(f"Total speed multiplier: {total_speed_multiplier:.2f}x")
    print(f"Final speed: {final_speed:.1f}")
    
    # Calculate manufacturing hours and gameplay time
    manufacturing_hours_per_real_hour = final_speed
    minutes_per_attempt = 60 / manufacturing_hours_per_real_hour
    average_attempts_for_change = 69  # for 1% chance
    average_hours_for_change = average_attempts_for_change * minutes_per_attempt / 60
    
    print()
    print("Timing Analysis:")
    print(f"Manufacturing hours per real hour: {manufacturing_hours_per_real_hour:.1f}")
    print(f"Minutes per attempt: {minutes_per_attempt:.1f}")
    print(f"Average time for quality change: {average_hours_for_change:.1f} hours")
    
    return final_speed, average_hours_for_change

if __name__ == "__main__":
    calculate_foundry_speed()