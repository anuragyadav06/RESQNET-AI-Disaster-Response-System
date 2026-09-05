"""
ResQNet Intelligence - Mission Risk Assessment Agent
"""
from typing import Dict, List, Optional, Tuple
from app.schemas.common import Vector3D
from app.schemas.mission import RiskAssessment
from app.schemas.drone import DroneEntity
from app.state.world_state import world_state


class RiskAgent:
    def __init__(self):
        pass

    def evaluate_route_risk(
        self,
        waypoints: List[Vector3D],
        drone: DroneEntity,
        estimated_flight_dist_m: float,
    ) -> RiskAssessment:
        contributors: List[str] = []
        overall_risk = 0.05  # Base flight operational risk

        # 1. Hazard Proximity (Fires, smoke, collapses)
        min_hazard_dist = 9999.0
        nearest_hazard_type = ""
        
        for pt in waypoints:
            for hid, hz in world_state.hazards.items():
                if not hz.active:
                    continue
                # Ground distance vs 3D altitude clearance
                ground_d = pt.ground_distance_to(hz.center)
                altitude_clearance = pt.y  # Drone altitude above ground
                
                if ground_d < min_hazard_dist:
                    min_hazard_dist = ground_d
                    nearest_hazard_type = hz.type.value
                
                # If flying high enough (>= 25m), thermal radiation is greatly attenuated
                if ground_d <= hz.radius_m:
                    if altitude_clearance >= 25.0:
                        overall_risk += 0.20
                        contributors.append(f"High-altitude overfly of {hz.type.value} corridor ({altitude_clearance:.0f}m alt)")
                    else:
                        overall_risk += 0.40
                        contributors.append(f"Low-altitude flight near {hz.type.value} zone ({ground_d:.1f}m)")
                elif ground_d <= (hz.radius_m + 30.0):
                    overall_risk += 0.10
                    contributors.append(f"Proximity buffer to active {hz.type.value} ({ground_d:.1f}m)")

        # 2. Battery Margin Assessment
        # Assume consumption: ~1% battery per 40m flight (including return)
        round_trip_dist = estimated_flight_dist_m * 2.0
        est_battery_needed = (round_trip_dist / 40.0)
        battery_margin = drone.battery_percent - est_battery_needed
        
        if battery_margin < 15.0:
            overall_risk += 0.45
            contributors.append(f"Critical battery margin ({battery_margin:.1f}% remaining after RTB)")
        elif battery_margin < 25.0:
            overall_risk += 0.20
            contributors.append(f"Tight battery reserve ({battery_margin:.1f}% remaining after RTB)")

        # 3. Communication Loss Probability
        comms_prob = (1.0 - drone.communication_quality) * 0.4
        if drone.communication_quality < 0.6:
            overall_risk += 0.20
            contributors.append(f"Degraded telemetry link ({drone.communication_quality*100:.0f}%)")

        # 4. Environmental conditions
        env = world_state.environment
        if env.wind_speed_mps > 10.0:
            overall_risk += 0.15
            contributors.append(f"High gusts ({env.wind_speed_mps} m/s)")
        if env.seismic_activity_richter > 4.0:
            overall_risk += 0.20
            contributors.append(f"Ongoing seismic aftershock ({env.seismic_activity_richter} Richter)")

        # Bound overall risk
        overall_risk = max(0.05, min(0.98, overall_risk))
        
        if overall_risk >= 0.80:
            category = "CRITICAL"
        elif overall_risk >= 0.55:
            category = "HIGH"
        elif overall_risk >= 0.25:
            category = "MODERATE"
        else:
            category = "LOW"

        if not contributors:
            contributors.append("Clear flight corridor with safe battery reserves")

        return RiskAssessment(
            overall_risk=round(overall_risk, 3),
            category=category,
            contributors=contributors,
            fire_proximity_m=round(min_hazard_dist, 1),
            battery_margin_percent=round(max(0.0, battery_margin), 1),
            comms_loss_probability=round(comms_prob, 3),
        )


risk_agent = RiskAgent()
