def calculate_midgame_assembler():
    """
    Calculate Assembler 3 + Speed 2 modules + 2 beacons
    """
    # Base stats
    assembler3_speed = 1.25

    # Direct modules: 4x Speed 2 modules
    speed2_bonus = 0.3  # 30% each
    direct_modules = 4
    direct_speed_bonus = direct_modules * speed2_bonus

    # Beacon calculation
    num_beacons = 2
    beacon_distribution = 1.5  # normal beacon distribution efficiency
    speed2_modules_per_beacon = 2

    # Transmission strength = distribution_efficiency * sqrt(num_beacons)
    transmission_strength = beacon_distribution * (num_beacons ** 0.5)

    # Each beacon has 2 speed 2 modules
    beacon_speed_bonus_per_beacon = speed2_modules_per_beacon * speed2_bonus
    total_beacon_speed_bonus = beacon_speed_bonus_per_beacon * transmission_strength

    # Final calculation
    total_speed_multiplier = 1 + direct_speed_bonus + total_beacon_speed_bonus
    final_speed = assembler3_speed * total_speed_multiplier

    print("Mid-Game Assembler 3 Speed Calculation:")
    print(f"Base Assembler 3 speed: {assembler3_speed}")
    print(f"Direct modules: {direct_modules}x Speed 2 (+{speed2_bonus*100}% each)")
    print(f"Direct speed bonus: +{direct_speed_bonus*100:.0f}%")
    print()
    print(f"Beacons: {num_beacons}x Normal beacons (distribution {beacon_distribution})")
    print(f"Modules per beacon: {speed2_modules_per_beacon}x Speed 2")
    print(f"Transmission strength: {beacon_distribution} × √{num_beacons} = {transmission_strength:.2f}")
    print(f"Beacon speed bonus per beacon: {beacon_speed_bonus_per_beacon*100:.0f}%")
    print(f"Total beacon speed bonus: {total_beacon_speed_bonus*100:.1f}%")
    print()
    print(f"Total speed multiplier: {total_speed_multiplier:.2f}x")
    print(f"Final speed: {final_speed:.2f}")

    # Calculate manufacturing hours and gameplay time
    manufacturing_hours_per_real_hour = final_speed
    minutes_per_attempt = 60 / manufacturing_hours_per_real_hour
    average_attempts_for_change = 69  # for 1% chance
    average_hours_for_change = average_attempts_for_change * minutes_per_attempt / 60

    print()
    print("Timing Analysis:")
    print(f"Manufacturing hours per real hour: {manufacturing_hours_per_real_hour:.2f}")
    print(f"Minutes per attempt: {minutes_per_attempt:.1f}")
    print(f"Average time for quality change: {average_hours_for_change:.1f} hours")

    return final_speed, average_hours_for_change

if __name__ == "__main__":
    calculate_midgame_assembler()