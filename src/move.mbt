// 新增：用于存储AI单位“意图”速度的 Map
let intent_velocities: Map[@system.Entity, @math.Vec2D] = Map::new()

// 新增：用于存储单位“避障”推力的 Map
let avoidance_vectors: Map[@system.Entity, @math.Vec2D] = Map::new()

struct MovementStats {
  speed: Double // 单位的基础移动速度
}

// 用 Map 存储拥有该组件的实体
let movement_stats: Map[@system.Entity, MovementStats] = Map::new()
// ---------------------------------
//  重构后的移动相关系统
// ---------------------------------

// 新系统 1: AI意图系统
// ---------------------------------
//  全新的、统一的NPC意图系统
// ---------------------------------
fn npc_intent_system(_backend: &@system.Backend) -> Unit {
  // 遍历所有单位
  for entity in all_units.val {
    // 这个系统不处理玩家的火车头
    if player_head.val == Some(entity) {
      continue
    }

    // 检查这个单位是不是玩家的小火车车厢
    if train_cars.get(entity) is Some(car_data) {
      // --- 行为模式 1：车厢跟随 ---
      if car_data.prev is Some(leader) {
        if entity.is_alive() && leader.is_alive() {
          if @position.positions.get(entity) is Some(car_pos) && 
             @position.positions.get(leader) is Some(leader_pos) {

            let distance = car_pos.0.distance_to(leader_pos.0)
            // 车厢的“意图”是：如果离领袖太远，就追上去
            if distance > TRAIN_SPACING {
              let direction = (leader_pos.0 - car_pos.0).normalize()
              let speed = 2.5 // 车厢可以稍微快一点，以便跟上
              intent_velocities.set(entity, direction.scalar_mul(speed))
            } else {
              // 如果距离合适，它的“意图”就是停下（但依然会受避障影响）
              intent_velocities.set(entity, @math.Vec2D(0.0, 0.0))
            }
          }
        }
      }
    } else {
      // --- 行为模式 2：普通AI单位（敌人）---
      // 这里的逻辑和我们之前的 ai_intent_system 完全一样
      if destinations.get(entity) is Some(dest) {
        if @position.positions.get(entity) is Some(pos) && movement_stats.get(entity) is Some(stats) {
          let distance = pos.0.distance_to(dest)
          if distance < 5.0 {
            destinations.remove(entity)
            intent_velocities.set(entity, @math.Vec2D(0.0, 0.0))
          } else {
            let direction = (dest - pos.0).normalize()
            intent_velocities.set(entity, direction.scalar_mul(stats.speed))
          }
        }
      } else {
        intent_velocities.set(entity, @math.Vec2D(0.0, 0.0))
      }
    }
  }
}

// 新系统 2: 避障系统
fn avoidance_system(_backend: &@system.Backend) -> Unit {
  // 这个系统只负责为所有单位计算避障推力
  for unit_a in all_units.val {
    let mut total_avoidance_vec = @math.Vec2D(0.0, 0.0)
    if @position.positions.get(unit_a) is Some(pos_a) && teams.get(unit_a) is Some(team_a) {
      if avoidance_behaviors.get(unit_a) is Some(behavior_a) {
        for unit_b in all_units.val {
          if unit_a != unit_b {
            if @position.positions.get(unit_b) is Some(pos_b) && teams.get(unit_b) is Some(team_b) {
              let distance = pos_a.0.distance_to(pos_b.0)
              if distance < behavior_a.avoidance_radius {
                let direction = (pos_a.0 - pos_b.0).normalize()
                let strength = (behavior_a.avoidance_radius - distance) / behavior_a.avoidance_radius
                let push_force = direction.scalar_mul(strength)
                if team_a != team_b {
                  total_avoidance_vec = total_avoidance_vec + push_force.scalar_mul(ENEMY_PUSH_FACTOR)
                } else {
                  total_avoidance_vec = total_avoidance_vec + push_force
                }
              }
            }
          }
        }
      }
    }
    avoidance_vectors.set(unit_a, total_avoidance_vec)
  }
}

// 新系统 3: 速度合成系统
// ---------------------------------
//  速度合成系统 (语法修正版)
// ---------------------------------
// ---------------------------------
//  速度合成系统 (类型修正版)
// ---------------------------------
pub fn velocity_resolver_system(_backend: &@system.Backend) -> Unit {
  for entity in all_units.val {
    let avoid_vec = match avoidance_vectors.get(entity) {
      Some(vec) => vec
      None => @math.Vec2D(0.0, 0.0)
    }
    
    let base_vel = if player_head.val == Some(entity) {
      // 玩家的“基础速度”来自它当前的 Velocity 组件
      match @velocity.velocities.get(entity) {
        // 【核心修正】从 Velocity "盒子" 中取出 Vec2D "东西"
        Some(vel_component) => vel_component.0
        None => @math.Vec2D(0.0, 0.0)
      }
    } else {
      // AI的“基础速度”来自它的意图，这已经是一个 Vec2D
      match intent_velocities.get(entity) {
        Some(vel) => vel
        None => @math.Vec2D(0.0, 0.0)
      }
    }

    // 现在 base_vel 和 avoid_vec 都是 Vec2D 类型，可以安全相加
    let final_vel = base_vel + avoid_vec.scalar_mul(AVOIDANCE_STRENGTH)
    
    // velocity.set 会自动将 Vec2D 包装成 Velocity 组件
    @velocity.velocities.set(entity, final_vel)
  }
}