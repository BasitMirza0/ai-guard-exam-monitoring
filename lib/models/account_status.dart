/// Approval status used by mobile routing and the admin review list.
/// Older profiles without a status still require review.
String accountStatus(Map<String, dynamic> profile) {
  final status = profile['status']?.toString().trim().toLowerCase();
  return const {'approved', 'rejected', 'pending'}.contains(status)
      ? status!
      : 'pending';
}
