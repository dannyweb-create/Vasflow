/// Option lists shared by the client form, applications, documents,
/// payments and reports screens. Single source so wording never drifts.
library;

/// Application lifecycle statuses.
const kApplicationStatuses = [
  'Draft',
  'Submitted',
  'Offer received',
  'Accepted',
  'Visa pending',
  'Visa approved',
  'Visa refused',
  'Withdrawn',
];

/// What kind of application is being tracked.
const kApplicationTypes = [
  'University admission',
  'Visa application',
  'Scholarship application',
  'Language course',
  'Other',
];

/// Levels of study for the academic section.
const kStudyLevels = [
  'Language course',
  'Foundation',
  'Diploma',
  'Undergraduate',
  'Postgraduate',
  'PhD',
  'Other',
];

/// Document categories used everywhere documents appear.
const kDocumentTypes = [
  'Passport',
  'Academic certificates',
  'Transcripts',
  'English test results',
  'CV',
  'Financial evidence',
  'Offer letter',
  'Visa forms',
  'Other supporting documents',
];

/// Fee types for payment records.
const kFeeTypes = [
  'Consultation fee',
  'Application fee',
  'Tuition deposit',
  'Visa fee',
  'Other',
];

/// Upcoming study intakes for the next two years.
List<String> intakeOptions() {
  final year = DateTime.now().year;
  return [
    'Flexible',
    for (final y in [year, year + 1]) ...[
      'Jan/Feb $y',
      'May/Jun $y',
      'Sep/Oct $y',
    ],
  ];
}

/// Keeps the status shown in a dropdown valid even when an older record
/// holds a value that is no longer listed.
String unionValue(List<String> options, String value) =>
    options.contains(value) ? value : options.first;
