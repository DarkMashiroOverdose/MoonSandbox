



struct MovementStats {
  speed: Double // 单位的基础移动速度
}

// 用 Map 存储拥有该组件的实体
let movement_stats: Map[@system.Entity, MovementStats] = Map::new()
// ---------------------------------
//  重构后的移动相关系统
// ---------------------------------

// 敌人之间的避让半径
const ENEMY_AVOIDANCE_RADIUS: Double = 100.0 
// 敌人之间的避让力度
const ENEMY_AVOIDANCE_STRENGTH: Double = 1.5

/// 职责：一个函数处理敌人的所有移动逻辑：追击 + 互相避让
pub fn enemy_movement_system(_backend: &@system.Backend) -> Unit {
  // 我们需要一个临时的 Map 来存储每个单位计算出的最终速度
  // 这样做是为了避免在一个循环中同时读取和写入 @velocity.velocities
  let final_velocities: Map[@system.Entity, @math.Vec2D] = Map::new()

  // --- 阶段一：为每个敌人计算它这一帧的最终速度 ---
  for entity in all_units.val {
    if teams.get(entity) is Some(Team::Enemy) {
      
      // 1. 计算“意图速度”(追击玩家或停下)
      let mut intent_vel = @math.Vec2D(0.0, 0.0)
      if attack_targets.get(entity) is Some(target) {
         if @position.positions.get(entity) is Some(enemy_pos) &&
            @position.positions.get(target) is Some(target_pos) &&
            combat_stats.get(entity) is Some(combat_stats) &&
            movement_stats.get(entity) is Some(move_stats) {
            
            if enemy_pos.0.distance_to(target_pos.0) > combat_stats.attack_range {
                let direction = (target_pos.0 - enemy_pos.0).normalize()
                intent_vel = direction.scalar_mul(move_stats.speed)
            }
         }
      }

      // 2. 计算“避障速度”(被其他敌人推开)
      let mut avoidance_vec = @math.Vec2D(0.0, 0.0)
      if @position.positions.get(entity) is Some(pos_a) {
        for other_enemy in all_units.val {
          if entity != other_enemy && teams.get(other_enemy) is Some(Team::Enemy) {
            if @position.positions.get(other_enemy) is Some(pos_b) {
              let distance = pos_a.0.distance_to(pos_b.0)
              if distance < ENEMY_AVOIDANCE_RADIUS {
                let direction = (pos_a.0 - pos_b.0).normalize()
                let strength = (ENEMY_AVOIDANCE_RADIUS - distance) / ENEMY_AVOIDANCE_RADIUS
                let push_force = direction.scalar_mul(strength)
                avoidance_vec = avoidance_vec + push_force
              }
            }
          }
        }
      }

      // 3. 合成最终速度，并存入我们的临时 Map
      let final_vel = intent_vel + avoidance_vec.scalar_mul(ENEMY_AVOIDANCE_STRENGTH)
      final_velocities.set(entity, final_vel)
    }
  }

  // --- 阶段二：将计算好的所有最终速度，一次性应用到 Velocity 组件上 ---
  for entity, final_vel in final_velocities {
    @velocity.velocities.set(entity, final_vel)
  }
}



// -- 碰撞常量 --
const PLAYER_PART_RADIUS: Double = 32.0 // 玩家每个部分的碰撞半径
const ENEMY_RADIUS: Double = 20.0       // 敌人的碰撞半径
const KNOCKBACK_STRENGTH: Double = 5.0  // 敌人被弹开的速度

fn collision_system(_backend: &@system.Backend) -> Unit {
  // 遍历所有敌人
  for enemy in all_units.val {
    if teams.get(enemy) is Some(Team::Enemy) {
      if @position.positions.get(enemy) is Some(enemy_pos) {

        // 让每个敌人去检查是否撞到了任何一个玩家单位
        for player_part in all_units.val {
          if teams.get(player_part) is Some(Team::Player) {
            if @position.positions.get(player_part) is Some(player_pos) {

              let distance = enemy_pos.0.distance_to(player_pos.0)
              // 如果距离小于两者半径之和，说明发生了碰撞
              if distance < (PLAYER_PART_RADIUS + ENEMY_RADIUS) {

                // 1. 计算反弹方向：从玩家指向敌人
                let knockback_direction = (enemy_pos.0 - player_pos.0).normalize()

                // 2. 为【敌人】设置一个短暂的反弹速度
                @velocity.velocities.set(enemy, knockback_direction.scalar_mul(KNOCKBACK_STRENGTH))

                // 3. （未来）在这里可以对玩家造成伤害
                // hurt_player(1)

                // 只要撞到了一个玩家单位，这个敌人就不再检查其他，跳出内层循环
                break 
              }
            }
          }
        }
      }
    }
  }
}