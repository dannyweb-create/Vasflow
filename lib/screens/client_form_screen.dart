import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/client_record.dart';
import '../models/options.dart';
import '../models/stages.dart';
import '../services/auth_service.dart';
import '../services/client_photo_service.dart';
import '../services/client_repository.dart';
import '../widgets/client_avatar.dart';

/// Full-screen client form with six organised sections (Personal, Academic,
/// Passport & travel, Application, Documents, Notes). "Documents" tracks the
/// status of each required document so sensitive files themselves stay out of
/// the device until the private vault in the Documents screen.
class ClientFormScreen extends StatefulWidget {
  final ClientRepository repo;
  final AuthService auth;
  final ClientRecord? existing;

  const ClientFormScreen({
    super.key,
    required this.repo,
    required this.auth,
    this.existing,
  });

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(
    text: widget.existing?.fullName ?? '',
  );
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _nationality = TextEditingController(
    text: '${widget.existing?.details['nationality'] ?? ''}',
  );
  late final _address = TextEditingController(
    text: '${widget.existing?.details['address'] ?? ''}',
  );
  late final _school = TextEditingController(
    text: '${widget.existing?.details['current_school'] ?? ''}',
  );
  late final _qualifications = TextEditingController(
    text: '${widget.existing?.details['qualifications'] ?? ''}',
  );
  late final _course = TextEditingController(
    text: '${widget.existing?.details['intended_course'] ?? ''}',
  );
  late final _country = TextEditingController(
    text: widget.existing?.country ?? '',
  );
  late final _university = TextEditingController(
    text: widget.existing?.university ?? '',
  );
  late final _passport = TextEditingController(
    text: widget.existing?.passportNumber ?? '',
  );
  late final _passportCountry = TextEditingController(
    text: '${widget.existing?.details['passport_country'] ?? ''}',
  );
  late final _consultant = TextEditingController(
    text: '${widget.existing?.details['consultant'] ?? ''}',
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late final _followUp = TextEditingController(
    text: '${widget.existing?.details['follow_up'] ?? ''}',
  );

  DateTime? _dob;
  DateTime? _passportIssue;
  DateTime? _passportExpiry;
  DateTime? _travelDate;
  DateTime? _deadline;
  String? _studyLevel;
  String? _intake;
  String? _appType;
  String _stage = kClientStages.first;
  String _visaStatus = 'Not started';
  String? _consultantName;
  Set<String> _docs = {};
  List<Map<String, dynamic>> _team = const [];
  bool _saving = false;
  late String _photoPath;
  Uint8List? _pendingPhoto;
  String _pendingPhotoExt = 'jpg';
  bool _removePhoto = false;

  final _today = DateTime.now();

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  String? _detailText(String key) {
    final existing = widget.existing?.details[key];
    final value = existing == null ? '' : '$existing'.trim();
    if (value.isEmpty || value == 'null') return null;
    return value;
  }

  static String _iso(DateTime? date) =>
      date == null ? '' : date.toIso8601String().substring(0, 10);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadTeam() async {
    try {
      final team = await widget.auth.listTeam();
      if (mounted) setState(() => _team = team);
    } catch (_) {
      // Without the team list the consultant field stays a plain text field.
    }
  }

  @override
  void initState() {
    super.initState();
    final details = widget.existing?.details ?? const {};
    _dob = ClientRecord.dateFromDetails(details, 'dob');
    _passportIssue = ClientRecord.dateFromDetails(
      details,
      'passport_issue_date',
    );
    _passportExpiry = ClientRecord.dateFromDetails(
      details,
      'passport_expiry_date',
    );
    _travelDate = ClientRecord.dateFromDetails(details, 'travel_date');
    _deadline = ClientRecord.dateFromDetails(details, 'application_deadline');
    _studyLevel = _detailText('study_level');
    _intake = _detailText('intake');
    _appType = _detailText('application_type');
    _stage =
        _detailText('stage') ?? widget.existing?.stage ?? kClientStages.first;
    _visaStatus =
        _detailText('visa_status') ??
        widget.existing?.visaStatus ??
        'Not started';
    _consultantName = _detailText('consultant');
    _docs = {...ClientRecord.receivedDocuments(details)};
    _photoPath = widget.existing?.photoPath ?? '';
    _loadTeam();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _nationality,
      _address,
      _school,
      _qualifications,
      _course,
      _country,
      _university,
      _passport,
      _passportCountry,
      _consultant,
      _notes,
      _followUp,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<ImageSource?> _choosePhotoSource() => showModalBottomSheet<ImageSource>(
    context: context,
    builder:
        (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Client photo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
  );

  Future<void> _pickPhoto() async {
    final source = await _choosePhotoSource();
    if (source == null) return;
    try {
      final file = await ClientPhotoService.pick(source);
      if (file == null) return;
      final ext = ClientPhotoService.extensionOf(file.name);
      if (!ClientPhotoService.isSupportedExtension(ext)) {
        _snack('Client photos must be JPG or PNG.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        _snack('That photo is too large. Choose a smaller image.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _pendingPhoto = bytes;
        _pendingPhotoExt = ext;
        _removePhoto = false;
      });
    } catch (e) {
      _snack('Could not pick a photo: ${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  Widget _photoEditor() {
    final hasPhoto =
        _pendingPhoto != null || (!_removePhoto && _photoPath.isNotEmpty);
    final avatar =
        _pendingPhoto != null
            ? ClipOval(
              child: Image.memory(
                _pendingPhoto!,
                width: 76,
                height: 76,
                fit: BoxFit.cover,
              ),
            )
            : ClientAvatar(
              photoPath: _removePhoto ? '' : _photoPath,
              name: _name.text,
              size: 76,
            );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(hasPhoto ? 'Change photo' : 'Add photo'),
                    ),
                    if (hasPhoto)
                      TextButton.icon(
                        onPressed:
                            () => setState(() {
                              _pendingPhoto = null;
                              _removePhoto = true;
                            }),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'JPG or PNG. Large photos are resized before upload.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      _snack('Fix the highlighted fields first.');
      return;
    }
    if (_dob != null && _dob!.isAfter(_today)) {
      _snack('Date of birth cannot be in the future.');
      return;
    }
    if (_passportIssue != null &&
        _passportExpiry != null &&
        _passportExpiry!.isBefore(_passportIssue!)) {
      _snack('Passport expiry must be after the issue date.');
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);

    final clientId = widget.existing?.id ?? widget.repo.local.newId();
    var photoPath = _removePhoto ? '' : _photoPath;
    String? oldPhotoToDelete;

    if (_pendingPhoto != null) {
      final workspaceId = widget.auth.workspaceId;
      if (workspaceId == null) {
        if (mounted) setState(() => _saving = false);
        _snack('Join or create a workspace before uploading a client photo.');
        return;
      }
      try {
        final newPath = await ClientPhotoService().upload(
          workspaceId: workspaceId,
          clientId: clientId,
          bytes: _pendingPhoto!,
          extension: _pendingPhotoExt,
        );
        if (_photoPath.isNotEmpty && _photoPath != newPath) {
          oldPhotoToDelete = _photoPath;
        }
        photoPath = newPath;
      } catch (e) {
        if (mounted) setState(() => _saving = false);
        _snack(
          'Photo upload failed: ${'$e'.replaceFirst('Exception: ', '')}',
        );
        return;
      }
    } else if (_removePhoto && _photoPath.isNotEmpty) {
      oldPhotoToDelete = _photoPath;
    }

    final consultantName =
        _team.isEmpty ? _consultant.text.trim() : (_consultantName ?? '');

    final details = {...?widget.existing?.details};
    details['dob'] = _iso(_dob);
    details['nationality'] = _nationality.text.trim();
    details['address'] = _address.text.trim();
    details['current_school'] = _school.text.trim();
    details['qualifications'] = _qualifications.text.trim();
    details['intended_course'] = _course.text.trim();
    details['study_level'] = _studyLevel ?? '';
    details['intake'] = _intake ?? '';
    details['passport_issue_date'] = _iso(_passportIssue);
    details['passport_expiry_date'] = _iso(_passportExpiry);
    details['passport_country'] = _passportCountry.text.trim();
    details['travel_date'] = _iso(_travelDate);
    details['application_type'] = _appType ?? '';
    details['application_deadline'] = _iso(_deadline);
    details['consultant'] = consultantName;
    details['docs_received'] = (_docs.toList()..sort());
    details['follow_up'] = _followUp.text.trim();

    final record = ClientRecord(
      id: clientId,
      fullName: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      country: _country.text.trim(),
      university: _university.text.trim(),
      passportNumber: _passport.text.trim(),
      notes: _notes.text.trim(),
      stage: _stage,
      visaStatus: _visaStatus,
      archived: widget.existing?.archived ?? false,
      photoPath: photoPath,
      details: details,
      updatedAt: DateTime.now(),
    );

    String message = 'Client saved';
    var onlineSaveFailed = false;
    try {
      await widget.repo.upsert(record);
    } catch (e) {
      onlineSaveFailed = true;
      message = 'Saved on this device. Online save failed: '
              '$e'
          .replaceFirst('Exception: ', '');
    }
    if (oldPhotoToDelete != null && !onlineSaveFailed) {
      try {
        await ClientPhotoService().remove(oldPhotoToDelete);
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context, true);
  }

  Widget _heading(IconData icon, String title) => Container(
    margin: const EdgeInsets.only(top: 18, bottom: 14),
    padding: const EdgeInsets.fromLTRB(2, 0, 0, 10),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    TextInputType? type,
    String? Function(String?)? validator,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      maxLines: lines,
      keyboardType: type,
      validator: validator,
      decoration: _decor(label).copyWith(hintText: hint),
      inputFormatters: [
        if (type == TextInputType.phone)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
      ],
    ),
  );

  Widget _dateField(
    String label,
    DateTime? value, {
    DateTime? first,
    required DateTime last,
    required ValueChanged<DateTime?> onChanged,
  }) {
    Future<void> pick() async {
      final picked = await showDatePicker(
        context: context,
        initialDate:
            value == null
                ? (first ?? last)
                : (value.isAfter(last) ? last : value),
        firstDate: first ?? DateTime(1930),
        lastDate: last,
      );
      if (picked != null) onChanged(picked);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: pick,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: _decor(label).copyWith(
            suffixIcon:
                value == null
                    ? const Icon(Icons.event_outlined)
                    : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Clear',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onChanged(null),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: pick,
                          icon: const Icon(Icons.event_outlined, size: 20),
                        ),
                      ],
                    ),
          ),
          child: Text(
            value == null ? '' : DateFormat('d MMM y').format(value),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(
    String? value,
    String label,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    final items = [
      ...options,
      if (value != null && value.isNotEmpty && !options.contains(value)) value,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: [
          for (final v in items)
            DropdownMenuItem(value: v, child: Text(v, maxLines: 1)),
        ],
        onChanged: onChanged,
        decoration: _decor(label),
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => Padding(
    padding: const EdgeInsets.only(bottom: 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ],
    ),
  );

  /// Read-only echoes for values that live in the Academic section, so the
  /// Application section shows the intended course/university once.
  Widget _echo(
    String label,
    TextEditingController controller,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder:
        (context, value, _) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$label: ${value.text.trim().isEmpty ? 'not set yet' : value.text.trim()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
  );

  List<Widget> personalSection() => [
    _heading(Icons.person_outline_rounded, 'Personal'),
    _photoEditor(),
    _field(
      _name,
      'Full name *',
      validator:
          (v) => (v?.trim().isEmpty ?? true) ? 'Full name is required' : null,
    ),
    _field(
      _email,
      'Email',
      type: TextInputType.emailAddress,
      validator: (v) {
        final value = v?.trim() ?? '';
        if (value.isEmpty) return null;
        return value.contains('@') && value.contains('.')
            ? null
            : 'Enter a valid email';
      },
    ),
    _field(_phone, 'Phone', type: TextInputType.phone),
    _dateField(
      'Date of birth',
      _dob,
      last: _today,
      onChanged: (d) => setState(() => _dob = d),
    ),
    _field(_nationality, 'Nationality'),
    _field(_address, 'Address', lines: 2),
  ];

  List<Widget> academicSection() => [
    _heading(Icons.school_outlined, 'Academic'),
    _field(_school, 'Current school'),
    _field(
      _qualifications,
      'Qualifications',
      lines: 2,
      hint: 'e.g. A-Levels, BSc Accounting',
    ),
    _field(_course, 'Intended course'),
    _dropdown(
      _studyLevel,
      'Study level',
      kStudyLevels,
      (v) => setState(() => _studyLevel = v),
    ),
    _field(_country, 'Preferred country'),
    _field(_university, 'Preferred university'),
    _dropdown(
      _intake,
      'Intake',
      intakeOptions(),
      (v) => setState(() => _intake = v),
    ),
  ];

  List<Widget> passportSection() => [
    _heading(Icons.travel_explore_outlined, 'Passport & travel'),
    _field(_passport, 'Passport number'),
    _pair(
      _dateField(
        'Issue date',
        _passportIssue,
        last: _today,
        onChanged: (d) => setState(() => _passportIssue = d),
      ),
      _dateField(
        'Expiry date',
        _passportExpiry,
        first: _today,
        last: DateTime(_today.year + 20),
        onChanged: (d) => setState(() => _passportExpiry = d),
      ),
    ),
    _field(_passportCountry, 'Country of issue'),
    _dateField(
      'Intended travel date',
      _travelDate,
      first: _today,
      last: DateTime(_today.year + 5),
      onChanged: (d) => setState(() => _travelDate = d),
    ),
  ];

  List<Widget> applicationSection() {
    final teamNames =
        _team
            .map((row) => '${row['display_name'] ?? ''}'.trim())
            .where((name) => name.isNotEmpty)
            .toList();
    return [
      _heading(Icons.send_outlined, 'Application'),
      _dropdown(
        _appType,
        'Application type',
        kApplicationTypes,
        (v) => setState(() => _appType = v),
      ),
      _echo('University', _university),
      _echo('Course', _course),
      _dropdown(
        _stage,
        'Application status (pipeline stage)',
        kClientStages,
        (v) => setState(() => _stage = v ?? kClientStages.first),
      ),
      _dropdown(_visaStatus, 'Visa status', const [
        'Not started',
        'In progress',
        'Approved',
        'Refused',
      ], (v) => setState(() => _visaStatus = v ?? 'Not started')),
      _dateField(
        'Application deadline',
        _deadline,
        first: DateTime(_today.year - 2),
        last: DateTime(_today.year + 5),
        onChanged: (d) => setState(() => _deadline = d),
      ),
      if (teamNames.isNotEmpty)
        _dropdown(
          _consultantName,
          'Assigned consultant',
          teamNames,
          (v) => setState(() => _consultantName = v),
        )
      else
        _field(_consultant, 'Assigned consultant'),
    ];
  }

  List<Widget> documentsSection() => [
    _heading(Icons.folder_open_outlined, 'Documents'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final doc in kDocumentTypes)
          FilterChip(
            selected: _docs.contains(doc),
            showCheckmark: true,
            onSelected:
                (on) => setState(() => on ? _docs.add(doc) : _docs.remove(doc)),
            label: Text(doc),
          ),
      ],
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Text(
        'Mark what has been received. File uploads open in the private '
        'Documents vault.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.65),
        ),
      ),
    ),
  ];

  List<Widget> notesSection() => [
    _heading(Icons.sticky_note_2_outlined, 'Notes'),
    _field(_notes, 'Additional information', lines: 3),
    _field(_followUp, 'Follow-up requirements', lines: 2),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add client' : 'Edit client'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: Icon(_saving ? Icons.hourglass_top : Icons.save_outlined),
          label: Text(widget.existing == null ? 'Save client' : 'Save changes'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            ...personalSection(),
            ...academicSection(),
            ...passportSection(),
            ...applicationSection(),
            ...documentsSection(),
            ...notesSection(),
          ],
        ),
      ),
    );
  }
}
