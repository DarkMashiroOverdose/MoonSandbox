



struct MovementStats {
  speed: Double // 单位的基础移动速度
}

// 用 Map 存储拥有该组件的实体
let movement_stats: Map[@system.Entity, MovementStats] = Map::new()
// ---------------------------------
//  重构后的移动相关系统
// ---------------------------------

pub fn enemy_movement_system(_backend: &@system.Backend) -> Unit {
  // 这个系统只负责驱动敌人的移动
  for entity in all_units.val {
    // 检查单位是否是敌人
    if teams.get(entity) is Some(Team::Enemy) {
      
      // 检查敌人是否有攻击目标
      if attack_targets.get(entity) is Some(target) {
         // 【核心修正】确保敌人同时拥有执行移动和判断距离所需的所有组件
         if @position.positions.get(entity) is Some(enemy_pos) &&
            @position.positions.get(target) is Some(target_pos) &&
            movement_stats.get(entity) is Some(move_stats) && // 获取移动属性
            combat_stats.get(entity) is Some(combat_stats) {   // 获取战斗属性
            
            // 如果不在攻击范围内，就计算速度去追击
            // 【核心修正】从 combat_stats 中读取 attack_range
            if enemy_pos.0.distance_to(target_pos.0) > combat_stats.attack_range {
                let direction = (target_pos.0 - enemy_pos.0).normalize()
                // 【核心修正】从 move_stats 中读取 speed
                @velocity.velocities.set(entity, direction.scalar_mul(move_stats.speed))
            } else {
                // 如果已进入攻击范围，则停下 (这个指令会被 combat_system 覆盖，但作为默认行为是好的)
                @velocity.velocities.set(entity, @math.Vec2D(0.0, 0.0))
            }
         }
      } else {
        // 如果敌人没有攻击目标，就让它停下
        @velocity.velocities.set(entity, @math.Vec2D(0.0, 0.0))
      }
    }
  }
}



// -- 碰撞常量 --
const PLAYER_PART_RADIUS: Double = 32.0 // 玩家每个部分的碰撞半径
const ENEMY_RADIUS: Double = 32.0       // 敌人的碰撞半径
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