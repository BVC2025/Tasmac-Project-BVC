class RejectionReasonOption {
  final String value;
  final String label;

  const RejectionReasonOption(this.value, this.label);
}

const List<RejectionReasonOption> rejectionReasons = [
  RejectionReasonOption('refund_qr_damaged', 'Refund QR damaged'),
  RejectionReasonOption('manufacturing_qr_damaged', 'Manufacturing QR damaged'),
  RejectionReasonOption('refund_qr_invalid', 'Refund QR invalid'),
  RejectionReasonOption('manufacturing_qr_invalid', 'Manufacturing QR invalid'),
  RejectionReasonOption('qr_already_used', 'QR already used / returned'),
  RejectionReasonOption('bottle_physically_damaged', 'Bottle physically damaged'),
  RejectionReasonOption('bottle_broken_cracked', 'Bottle broken / cracked'),
  RejectionReasonOption('bottle_tampered', 'Bottle tampered'),
  RejectionReasonOption('bottle_not_eligible', 'Bottle not eligible for refund'),
  RejectionReasonOption('other', 'Other / Unknown issue'),
];
