/// Where income can come from. Borrowed money is left out on purpose: it is a
/// debt, and counting it as income would make a balance look healthier than
/// it is.
const List<String> incomeSources = [
  'Allowance',
  'Salary',
  // Pay by the day or the hour, set aside for bills like a salary.
  'Wage',
  'Part-time Job',
  'Business',
  'Freelance',
  'Scholarship',
  'Gift',
  'Sold Something',
  'Refund',
  // What a bank or e-wallet pays on the money kept there.
  'Interest',
  'Other',
];

/// Picking this asks the user to say where the money came from in their own
/// words, so "Other" never has to stand in for the real answer.
const String otherIncomeSource = 'Other';
