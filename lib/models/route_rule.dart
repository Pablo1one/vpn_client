// пользовательское правило маршрутизации (shadowrocket-подобное): что куда гнать.
// action - куда (напрямую/через vpn/блок), match - по чему матчить, value - значение.
enum RuleAction { direct, proxy, block }

enum RuleMatch { domainSuffix, domainKeyword, ipCidr, process }

class RouteRule {
  final RuleAction action;
  final RuleMatch match;
  final String value;

  const RouteRule({
    required this.action,
    required this.match,
    required this.value,
  });

  // ключ правила в sing-box route (domain_suffix/domain_keyword/ip_cidr/process_name)
  String get singboxField => switch (match) {
        RuleMatch.domainSuffix => 'domain_suffix',
        RuleMatch.domainKeyword => 'domain_keyword',
        RuleMatch.ipCidr => 'ip_cidr',
        RuleMatch.process => 'process_name',
      };

  Map<String, dynamic> toJson() =>
      {'action': action.name, 'match': match.name, 'value': value};

  factory RouteRule.fromJson(Map<String, dynamic> j) => RouteRule(
        action: RuleAction.values.byName(j['action'] as String),
        match: RuleMatch.values.byName(j['match'] as String),
        value: j['value'] as String,
      );
}
