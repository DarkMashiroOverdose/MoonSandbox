/// ------------------------
/// 战斗与寻敌系统
/// ------------------------
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
  pub aoe_radius: Double 
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
                execute_bullet_attack(attacker, target, attacker_stats)
              }
              AttackType::Ranged => {
                //TODO: 实现远程瞬间伤害逻辑
                println("[Log] Ranged Attack not implemented yet.")
              }
              AttackType::AoE => {
                execute_aoe_melee_attack(attacker, attacker_stats)
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
fn execute_aoe_melee_attack(attacker: @system.Entity, stats: CombatStats) -> Unit {
  if @position.positions.get(attacker) is Some(attacker_pos) && teams.get(attacker) is Some(attacker_team) {
    println("[Log] Executing AoE Melee Attack from \{attacker}")
    
    let damage = stats.attack_damage
    effect_apply_aoe_damage(attacker_pos.0, stats.aoe_radius, stats.attack_damage, attacker_team)
  }
}
/// ------------------------
/// 伤害与战斗模块
/// ------------------------
fn apply_damage(target: @system.Entity, damage: Double) -> Unit {
  if healths.get(target) is Some(health) {
    let new_health = { ..health, current: health.current - damage }
    healths.set(target, new_health)
  }
}
fn execute_melee_attack(attacker: @system.Entity, target: @system.Entity, stats: CombatStats) -> Unit {
  println("[Log] Executing Melee Attack from \{attacker} to \{target}")
  effect_apply_single_target_damage(target, stats.attack_damage)
}

fn effect_apply_single_target_damage(target: @system.Entity, damage: Double) -> Unit {
  // 这个逻辑其实就是 apply_damage，我们可以直接复用它
  apply_damage(target, damage)
}

/// 效果函数2：以某个点为中心，对范围内的敌方单位造成伤害
fn effect_apply_aoe_damage(
  origin_pos: @math.Vec2D, 
  radius: Double, 
  damage: Double, 
  source_team: Team
) -> Unit {
  // 遍历所有单位，检查是否在范围内且为敌方
  for unit in all_units.val {
    // 检查单位是否为敌方
    if teams.get(unit) is Some(unit_team) && unit_team != source_team {
      if @position.positions.get(unit) is Some(unit_pos) {
        // 检查是否在伤害半径内
        if unit_pos.0.distance_to(origin_pos) <= radius {
          apply_damage(unit, damage)
        }
      }
    }
  }
}

/// 效果函数3：对单个目标施加 Debuff (当前为占位符)
fn effect_apply_debuff(target: @system.Entity, effect: DebuffType, duration: Double) -> Unit {
  // 直接调用简化的 apply_debuff 占位符函数
  apply_debuff(target, effect, duration)
}
