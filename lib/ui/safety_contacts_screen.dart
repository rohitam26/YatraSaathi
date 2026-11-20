import 'package:flutter/material.dart';
import '../models/safety_contact.dart';
import '../services/journey_repository.dart';
import '../services/messaging_service.dart';
import '../services/phone_number_helper.dart';

/// Screen providing comprehensive management for trusted safety contacts.
///
/// Supports adding multiple contacts (Mother, Father, Partner, Friend),
/// editing details, marking primary contact, and deleting contacts with confirmation.
class SafetyContactsScreen extends StatefulWidget {
  const SafetyContactsScreen({
    super.key,
    required this.repository,
  });

  final JourneyRepository repository;

  @override
  State<SafetyContactsScreen> createState() => _SafetyContactsScreenState();
}

class _SafetyContactsScreenState extends State<SafetyContactsScreen> {
  List<SafetyContact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final list = await widget.repository.getSafetyContacts();
    if (mounted) {
      setState(() {
        _contacts = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddEditDialog([SafetyContact? existing]) async {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phoneNumber ?? '');
    String countryCode = existing?.countryCode ?? '+91';
    String relation = existing?.relationship ?? 'Emergency Contact';
    bool isPrimary = existing?.isPrimary ?? (_contacts.isEmpty);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(isEditing ? 'Edit Safety Contact' : 'Add Safety Contact'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Contact Name *',
                          hintText: 'e.g. Mother, Rahul',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter contact name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: relation,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Relationship / Role',
                          prefixIcon: Icon(Icons.people_outline),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Mother', child: Text('Mother')),
                          DropdownMenuItem(value: 'Father', child: Text('Father')),
                          DropdownMenuItem(value: 'Partner', child: Text('Partner')),
                          DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                          DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                          DropdownMenuItem(value: 'Colleague', child: Text('Colleague')),
                          DropdownMenuItem(
                            value: 'Emergency Contact',
                            child: Text('Emergency Contact'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDlgState(() => relation = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 105,
                            child: DropdownButtonFormField<String>(
                              initialValue: countryCode,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Code',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: '+91', child: Text('+91')),
                                DropdownMenuItem(value: '+1', child: Text('+1')),
                                DropdownMenuItem(value: '+44', child: Text('+44')),
                                DropdownMenuItem(value: '+61', child: Text('+61')),
                                DropdownMenuItem(value: '+971', child: Text('+971')),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setDlgState(() => countryCode = v);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Mobile Number *',
                                hintText: '9876543210',
                                prefixIcon: Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter phone number';
                                }
                                if (!PhoneNumberHelper.isValidFormat(val, defaultCountryCode: countryCode)) {
                                  return 'Enter a valid number (e.g. 9876543210)';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Supports Indian & international numbers. WhatsApp account verification occurs in WhatsApp.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Primary Emergency Contact'),
                        subtitle: const Text('Default recipient for all stops'),
                        value: isPrimary,
                        onChanged: (val) {
                          setDlgState(() => isPrimary = val);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      final normalized = PhoneNumberHelper.normalizeToE164(
                        phoneCtrl.text.trim(),
                        defaultCountryCode: countryCode,
                      );
                      final contact = SafetyContact(
                        id: existing?.id ??
                            'contact_${DateTime.now().millisecondsSinceEpoch}',
                        name: nameCtrl.text.trim(),
                        phoneNumber: normalized,
                        countryCode: countryCode,
                        relationship: relation,
                        isPrimary: isPrimary,
                        createdAt: existing?.createdAt ?? DateTime.now(),
                      );
                      widget.repository.saveSafetyContact(contact).then((_) {
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop(true);
                        }
                      });
                    }
                  },
                  child: Text(isEditing ? 'Save Changes' : 'Add Contact'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      await _loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing ? 'Contact updated successfully.' : 'Contact added successfully.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(SafetyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Safety Contact?'),
        content: Text(
          'Remove "${contact.name}" (${contact.relationship}) from your trusted emergency contacts?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.deleteSafetyContact(contact.id);
      await _loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact removed successfully.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Safety Contacts',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? _buildEmptyState(theme, colorScheme)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _contacts.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildHeaderBanner(theme, colorScheme);
                    }
                    final contact = _contacts[index - 1];
                    return _buildContactCard(theme, colorScheme, contact);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Contact'),
      ),
    );
  }

  Widget _buildHeaderBanner(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withAlpha(50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withAlpha(40)),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.verified_user, color: colorScheme.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Multi-Contact Emergency Network',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Assign contacts to journeys or specific stops. Check-in SMS opens directly in your messaging app.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(80),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Safety Contacts Added',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add family members, partners or friends. When you arrive at your destination, STOP Vanthachu prepares an automated check-in message for them.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.person_add),
              label: const Text('Add First Emergency Contact'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(
    ThemeData theme,
    ColorScheme colorScheme,
    SafetyContact contact,
  ) {
    return Card(
      elevation: contact.isPrimary ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: contact.isPrimary
            ? BorderSide(color: colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: contact.isPrimary
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              child: Text(
                contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: contact.isPrimary ? Colors.white : colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'PRIMARY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.badge_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        contact.relationship,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.phone_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        contact.formattedPhoneNumber,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'primary') {
                  widget.repository.setPrimaryContact(contact.id).then((_) {
                    _loadContacts();
                  });
                } else if (val == 'whatsapp') {
                  const messaging = CompliantSmsMessagingService();
                  messaging.sendWhatsAppMessage(
                    phoneNumber: contact.formattedPhoneNumber,
                    message: 'Hi ${contact.name}, I have set you as an emergency contact on STOP Vanthachu.',
                  ).then((status) {
                    if (status == MessageDeliveryStatus.failed && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open WhatsApp. Ensure WhatsApp is installed. WhatsApp account existence can only be confirmed inside WhatsApp.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  });
                } else if (val == 'edit') {
                  _showAddEditDialog(contact);
                } else if (val == 'delete') {
                  _confirmDelete(contact);
                }
              },
              itemBuilder: (context) => [
                if (!contact.isPrimary)
                  const PopupMenuItem(
                    value: 'primary',
                    child: Row(
                      children: [
                        Icon(Icons.star_outline, size: 18),
                        SizedBox(width: 8),
                        Text('Set as Primary'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'whatsapp',
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Text('Open WhatsApp Chat'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit Contact'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
