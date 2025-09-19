
// 用 Map 存储拥有该组件的实体
let combat_stats: Map[@system.Entity, CombatStats] = Map::new()

// 新增：用于存储“谁正在攻击谁”的 Map
// Key: 攻击者, Value: 被攻击的目标
let attack_targets: Map[@system.Entity, @system.Entity] = Map::new()

pub struct CombatStats {
  pub attack_range: Double
  pub attack_damage: Double
  pub attack_cooldown: Double
  pub current_cooldown: Double
  pub aggro_range: Double
  pub attack_type: AttackType // 【新增】攻击类型
}

pub enum AttackType {
  Melee   // 近战
  Bullet  // 子弹攻击
  Ranged  // 长距离直接攻击
  AoE     // 近战范围伤害
} derive(Show)
fn combat_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0

  // 攻击冷却循环
  for unit in combat_stats.keys() {
    if combat_stats.get(unit) is Some(stats) {
      if stats.current_cooldown > 0.0 {
        let new_cooldown = stats.current_cooldown - delta_seconds
        combat_stats.set(unit, { ..stats, current_cooldown: new_cooldown })
      }
    }
  }

  //选择攻击对象和执行攻击
  attack_targets.each(fn(attacker, target) {
    if target.is_alive() && healths.get(target) is Some(_) {
      if combat_stats.get(attacker) is Some(attacker_stats) && 
         @position.positions.get(attacker) is Some(attacker_pos) &&
         @position.positions.get(target) is Some(target_pos) {

        let distance = attacker_pos.0.distance_to(target_pos.0)
        if distance > attacker_stats.attack_range {
          destinations.set(attacker, target_pos.0)
        } else {
          destinations.remove(attacker)

          if attacker_stats.current_cooldown <= 0.0 {
            // 重置冷却
            combat_stats.set(attacker, { ..attacker_stats, current_cooldown: attacker_stats.attack_cooldown })

            //根据攻击类型进行调度
            match attacker_stats.attack_type {
              AttackType::Melee => {
                execute_melee_attack(attacker, target, attacker_stats)
              }
              AttackType::Bullet => {
                spawn_projectile(attacker, target, attacker_stats)
              }
              AttackType::Ranged => {
                //TODO: 实现远程瞬间伤害逻辑
                println("[Log] Ranged Attack not implemented yet.")
              }
              AttackType::AoE => {
                //TODO: 实现范围伤害逻辑
                println("[Log] AoE Attack not implemented yet.")
              }
            }
          }
        }
      }
    } else {
      attack_targets.remove(attacker)
    }
  })

  // 处理死亡单位
  for unit in all_units.val {
    if unit.is_alive() {
      if healths.get(unit) is Some(health) && health.current <= 0.0 {
        // 将死亡单位加入待清理列表，交由 cleanup_system 处理。
        entities_to_cleanup.val.push(unit)
        // 将血量设为-1，防止下一帧被重复添加。
        healths.set(unit, {..health, current: -1.0})
      }
    }
  }
}

fn aggro_system(_backend: &@system.Backend) -> Unit {
  // 遍历所有单位
  for unit_a in all_units.val {
    // 检查单位 a 是否空闲，并且获取它的阵营
    let is_idle = attack_targets.get(unit_a) is None && destinations.get(unit_a) is None
    if is_idle && teams.get(unit_a) is Some(team_a) {

      let mut closest_target = None
      let mut min_distance = 99999.0

      if @position.positions.get(unit_a) is Some(pos_a) {
        // 再次遍历所有单位，寻找一个不同阵营的目标
        for unit_b in all_units.val {
          if teams.get(unit_b) is Some(team_b) {

            // 【核心修正】只要阵营不同，就是潜在目标！
            if team_a != team_b {
              if @position.positions.get(unit_b) is Some(pos_b) {
                let distance = pos_a.0.distance_to(pos_b.0)

                if combat_stats.get(unit_a) is Some(stats) && 
                   distance < stats.aggro_range && 
                   distance < min_distance {

                  min_distance = distance
                  closest_target = Some(unit_b)
                }
              }
            }
          }
        }
      }

      if closest_target is Some(target) {
        println("[Log] Aggro System: Unit \{unit_a} (\{team_a}) auto-targeting \{target}")
        attack_targets.set(unit_a, target)
      }
    }
  }
}

fn execute_melee_attack(attacker: @system.Entity, target: @system.Entity, stats: CombatStats) -> Unit {
  println("[Log] Executing Melee Attack from \{attacker} to \{target}")
  if healths.get(target) is Some(target_health) {
     let new_current_health = target_health.current - stats.attack_damage
     let new_health_component = { ..target_health, current: new_current_health }
     healths.set(target, new_health_component)
  }
}

// 使用子弹进行远程攻击
fn spawn_projectile(attacker: @system.Entity, target: @system.Entity, stats: CombatStats) -> Unit {
  //占位符
  println("[Log] Spawning Projectile from \{attacker} to \{target}")
}