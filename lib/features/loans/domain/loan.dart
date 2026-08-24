import 'dart:math' as math;

import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';

class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.outstanding,
    this.lender,
    this.type = LoanType.other,
    this.principal = 0,
    this.roi = 0,
    this.emi = 0,
    this.foreclosureChargePct = 0,
    this.interestPaid = 0,
    this.chargesPaid = 0,
    this.startDate,
    this.endDate,
    this.status = LoanStatus.active,
    this.note = '',
    this.currency = 'INR',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final num outstanding;
  final String? lender;
  final LoanType type;
  final num principal;

  /// Annual rate of interest, percent (e.g. 7.25).
  final num roi;
  final num emi;
  final num foreclosureChargePct;
  final num interestPaid;
  final num chargesPaid;
  final DateTime? startDate;
  final DateTime? endDate;
  final LoanStatus status;
  final String note;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == LoanStatus.active;
  num get paid => (principal - outstanding).clamp(0, principal);
  double get progress =>
      principal <= 0 ? 0 : (paid / principal).clamp(0, 1).toDouble();

  /// Monthly interest portion at the current outstanding — the figure the loan
  /// card shows next to the EMI.
  num get monthlyInterest => outstanding * (roi / 100) / 12;

  /// Remaining months on a reducing-balance schedule. Null when the EMI cannot
  /// service the interest (the loan would never amortise).
  int? get monthsRemaining {
    if (emi <= 0 || outstanding <= 0) return null;
    final r = roi / 100 / 12;
    if (r <= 0) return (outstanding / emi).ceil();
    if (emi <= outstanding * r) return null; // EMI too low to amortise
    final n = -math.log(1 - (outstanding * r / emi)) / math.log(1 + r);
    return n.isFinite && n > 0 ? n.ceil() : null;
  }

  factory Loan.fromJson(Map<String, dynamic> json) => Loan(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    outstanding: J.number(json['outstanding']),
    lender: J.strOrNull(json['lender']),
    type: LoanType.fromApi(J.strOrNull(json['type'])),
    principal: J.number(json['principal']),
    roi: J.number(json['roi']),
    emi: J.number(json['emi']),
    foreclosureChargePct: J.number(json['foreclosureChargePct']),
    interestPaid: J.number(json['interestPaid']),
    chargesPaid: J.number(json['chargesPaid']),
    startDate: J.date(json['startDate']),
    endDate: J.date(json['endDate']),
    status: LoanStatus.fromApi(J.strOrNull(json['status'])),
    note: J.str(json['note']),
    currency: J.str(json['currency'], 'INR'),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'outstanding': outstanding,
    if (lender != null) 'lender': lender,
    'type': type.api,
    'principal': principal,
    'roi': roi,
    'emi': emi,
    'foreclosureChargePct': foreclosureChargePct,
    if (startDate != null) 'startDate': startDate!.toUtc().toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
    'status': status.api,
    'note': note,
    'currency': currency,
  };
}
