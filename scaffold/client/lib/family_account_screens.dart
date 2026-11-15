// OLIVE BRANCH — the optional family account, on a grown-up's phone. Verified headless
// (client/test/family_account_screens_test.dart). MASTERFILE section 8.5.13.
//
// Reached only from a grown-up's Settings, under Account ("Family account"). It is NEVER reachable from a child's
// app, and a test fails if a child-side file imports this one. A child sees no PIN, code, count or error from any
// of it (P1 to P11).
//
// What is on these screens, in order of the real routes:
//   [FamilyAccountScreen]    the hub: where things stand, and what to do next. Resumes by itself.
//   [CreateAccountScreen]    invite-only sign-up: the invite code from whoever runs the server, your name, your time
//                            zone, a PIN for the account.
//   [SignInScreen]           check this phone's sign-in, or sign in on a new phone with a code from a signed-in one.
//   [AddChildScreen]         her first name, birth date, time zone, and your PIN.
//   [InviteGrownUpScreen]    invite another grown-up (your PIN); gives a code to hand over. Olive does not send it.
//   [JoinInviteScreen]       "I was invited": the code, who it is for, your name; waiting for their yes.
//   [ConfirmGrownUpScreen]   the inviter's yes (your PIN) or no. The only step that gives the other grown-up access.
//   [SetAccountPinScreen]    the PIN of an account made from an invite, which starts without one.
//
// Plain words for every failure ([problemFor]); no server code is ever on a screen. Nothing typed is kept: the PIN
// boxes are cleared the moment a request is sent, and every screen asks the phone to block screenshots while a code
// or PIN is on it ([SensitiveScreen]).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, FilteringTextInputFormatter, TextInputFormatter;

import 'family_account_logic.dart';
import 'family_account_service.dart';
import 'family_account_store.dart' show JoinStage, PendingJoin;
import 'local_family.dart' show HomeZone, kHomeZoneDevice, kHomeZones;
import 'pairing_redeem_screen.dart' show PairingRedeemScreen;
import 'screen_privacy.dart' show SensitiveScreen;

/// The zones an account can be set to: the phone's own list without "same as this phone" (the server needs a real
/// region name, and the phone has no zone database to turn "this phone" into one).
List<HomeZone> get accountTimeZones =>
    <HomeZone>[for (final HomeZone z in kHomeZones) if (z.id != kHomeZoneDevice) z];

// ---- shared pieces ----------------------------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children, this.sensitive = true});
  final String title;
  final List<Widget> children;
  final bool sensitive;

  @override
  Widget build(BuildContext context) {
    final Widget body = Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ),
      ),
    );
    return sensitive ? SensitiveScreen(child: body) : body;
  }
}

class _ProblemBox extends StatelessWidget {
  const _ProblemBox(this.problem);
  final AccountProblem? problem;

  @override
  Widget build(BuildContext context) {
    final AccountProblem? p = problem;
    if (p == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Card(
          key: const Key('accountProblem'),
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.message, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _PinBox extends StatelessWidget {
  const _PinBox({super.key, required this.controller, required this.label, this.enabled = true});
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          enabled: enabled,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: ''),
        ),
      );
}

class _TextBox extends StatelessWidget {
  const _TextBox({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.enabled = true,
    this.keyboard,
    this.maxLength,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;
  final TextInputType? keyboard;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboard,
          maxLength: maxLength,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
              labelText: label, hintText: hint, border: const OutlineInputBorder(), counterText: ''),
        ),
      );
}

class _ZonePicker extends StatelessWidget {
  const _ZonePicker({super.key, required this.value, required this.onChanged, required this.label, this.enabled = true});
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: <DropdownMenuItem<String>>[
            for (final HomeZone z in accountTimeZones) DropdownMenuItem<String>(value: z.id, child: Text(z.label)),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      );
}

/// Runs [body] while [setBusy] is true; turns every failure into an [AccountProblem] for [setProblem].
Future<T?> _guarded<T>(
  Future<T> Function() body, {
  required AccountAction action,
  required void Function(bool) setBusy,
  required void Function(AccountProblem?) setProblem,
}) async {
  setBusy(true);
  setProblem(null);
  try {
    final T r = await body();
    return r;
  } catch (e) {
    setProblem(problemFor(e, action));
    return null;
  } finally {
    setBusy(false);
  }
}

String _dateWords(DateTime d) {
  const List<String> m = <String>[
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
    'November', 'December',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

// ---- the hub -------------------------------------------------------------------------------------

class FamilyAccountScreen extends StatefulWidget {
  const FamilyAccountScreen({
    super.key,
    required this.service,
    this.suggestedName,
    this.suggestedChildName,
    this.suggestedZone,
    this.suggestedChildAge,
    this.onCodeRedeemed,
    this.baseUrl = '',
  });

  final FamilyAccountService service;

  /// From the family already set up on this phone, to save typing. Never sent anywhere until a grown-up submits.
  final String? suggestedName;
  final String? suggestedChildName;
  final String? suggestedZone;
  final int? suggestedChildAge;

  /// Called with the result of redeeming a sign-in code from another phone (see [SignInScreen]).
  final Future<void> Function(Map<String, dynamic> result)? onCodeRedeemed;

  /// For the redeem screen only.
  final String baseUrl;

  @override
  State<FamilyAccountScreen> createState() => _FamilyAccountScreenState();
}

class _FamilyAccountScreenState extends State<FamilyAccountScreen> {
  AccountSnapshot? _snap;
  AccountProblem? _problem;
  bool _loading = true;
  bool _busy = false;
  String? _joinNote;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    final AccountSnapshot s = await widget.service.snapshot();
    if (!mounted) return;
    setState(() {
      _snap = s;
      _loading = false;
    });
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (BuildContext _) => screen));
    if (mounted) unawaited(_reload());
  }

  Future<void> _checkJoin() async {
    final JoinStatus? r = await _guarded<JoinStatus>(widget.service.checkJoin,
        action: AccountAction.checkJoin,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (r == null || !mounted) return;
    setState(() => _joinNote = switch (r) {
          JoinStatus.waiting => "They haven't answered yet. Nothing is wrong; you can check again later.",
          JoinStatus.confirmed => "They said yes. You're now part of the family.",
          JoinStatus.turnedAway => 'They decided not to add you this time. You can talk to them about it.',
          JoinStatus.over => 'That invite ran out or was cancelled. Ask them to send a new one.',
        });
    if (r != JoinStatus.waiting) unawaited(_reload());
  }

  Future<void> _signOut() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Sign out of this account?'),
        content: const Text('Everything on this phone stays, including your family set up here. This phone stops '
            'sharing with the account until you sign in again.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay signed in')),
          FilledButton(key: const Key('confirmSignOut'), onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final bool? confirmed = await _guarded<bool>(widget.service.signOut,
        action: AccountAction.signOut,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (!mounted || confirmed == null) return;
    setState(() => _joinNote = confirmed
        ? 'You are signed out.'
        : 'You are signed out on this phone. The server could not be reached, so it may still count this phone as '
            'signed in until a grown-up removes it from another device.');
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final AccountSnapshot? s = _snap;
    return _Page(
      title: 'Family account',
      sensitive: false,
      children: <Widget>[
        if (_loading && s == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (s != null) ..._body(s),
      ],
    );
  }

  List<Widget> _body(AccountSnapshot s) {
    final ThemeData theme = Theme.of(context);
    return <Widget>[
      const _Note(
        key: Key('accountOptionalNote'),
        'An account is optional. Olive works fully on this phone without one. An account lets the grown-ups in a '
        'family share from different phones, through your own Olive server. Your child never sees any of this.',
      ),
      _ProblemBox(_problem),
      if (_joinNote != null) _Note(_joinNote!, key: const Key('accountNote')),
      if (s.unsavedSignIn) _unsavedBanner(theme),
      if (!s.signedIn) ..._signedOut(s) else ..._signedIn(s),
    ];
  }

  Widget _unsavedBanner(ThemeData theme) => Card(
        key: const Key('unsavedSignIn'),
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('This phone could not keep your sign-in. It works for now, but it will be lost when you close '
                'Olive, and the server cannot give it to you again.'),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('retrySaveSignIn'),
              onPressed: () async {
                final bool ok = await widget.service.retrySaveSignIn();
                if (!mounted) return;
                setState(() => _joinNote = ok ? 'Saved. This phone will stay signed in.' : 'Still could not save it. '
                    'Free some space on the phone and try again.');
                unawaited(_reload());
              },
              child: const Text('Try saving again'),
            ),
          ]),
        ),
      );

  List<Widget> _signedOut(AccountSnapshot s) => <Widget>[
        if (s.joining != null)
          Card(
            key: const Key('finishJoining'),
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('You started joining a family'),
              subtitle: const Text('Pick up where you left off.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go(JoinInviteScreen(service: widget.service, resume: s.joining)),
            ),
          ),
        _Tile(
          key: const Key('tileCreateAccount'),
          icon: Icons.person_add_alt_1_outlined,
          title: 'Make an account',
          subtitle: 'You need an invite code from whoever runs your Olive server.',
          onTap: () => _go(CreateAccountScreen(
              service: widget.service, suggestedName: widget.suggestedName, suggestedZone: widget.suggestedZone)),
        ),
        _Tile(
          key: const Key('tileSignIn'),
          icon: Icons.login,
          title: 'Sign in',
          subtitle: 'Already have an account? Use this phone with it.',
          onTap: () => _go(SignInScreen(
              service: widget.service, baseUrl: widget.baseUrl, onCodeRedeemed: widget.onCodeRedeemed)),
        ),
        _Tile(
          key: const Key('tileJoin'),
          icon: Icons.mail_outline,
          title: 'I was invited',
          subtitle: 'Another grown-up sent you an invite code for their child.',
          onTap: () => _go(JoinInviteScreen(service: widget.service)),
        ),
      ];

  List<Widget> _signedIn(AccountSnapshot s) {
    final ThemeData theme = Theme.of(context);
    return <Widget>[
      Card(
        child: ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Signed in on this phone'),
          subtitle: Text(s.serverReached
              ? 'Your account is working.'
              : "Olive couldn't reach the server just now, so this shows what this phone remembers."),
          trailing: IconButton(
              key: const Key('refreshAccount'),
              tooltip: 'Check again',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh)),
        ),
      ),
      if (s.hasPin == false)
        _Tile(
          key: const Key('tileSetPin'),
          icon: Icons.pin_outlined,
          title: 'Set a PIN for your account',
          subtitle: 'Adding a child or confirming a grown-up asks for it. It is not the PIN for this phone.',
          onTap: () => _go(SetAccountPinScreen(service: widget.service)),
        ),
      if (s.joining != null && s.joining!.stage == JoinStage.waiting) _waitingCard(),
      if (s.joining != null && s.joining!.stage == JoinStage.accepted)
        Card(
          key: const Key('finishJoining'),
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('You opened an invite and did not finish'),
            subtitle: const Text('Pick up where you left off.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _go(JoinInviteScreen(service: widget.service, resume: s.joining)),
          ),
        ),
      if (s.step == AccountStep.addChild)
        _Tile(
          key: const Key('tileAddChild'),
          icon: Icons.child_care,
          title: 'Add your child',
          subtitle: s.hasPin == false
              ? 'Set your account PIN first.'
              : 'Her first name, birth date and time zone. You will be her guardian on the account.',
          onTap: s.hasPin == false
              ? () => _go(SetAccountPinScreen(service: widget.service))
              : () => _go(AddChildScreen(
                  service: widget.service,
                  suggestedName: widget.suggestedChildName,
                  suggestedZone: widget.suggestedZone,
                  localAge: widget.suggestedChildAge)),
        ),
      if (s.children.isNotEmpty) ...<Widget>[
        Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('On this account', style: theme.textTheme.titleMedium)),
        for (final AccountChild c in s.children)
          Card(
            key: Key('child_${c.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              ListTile(
                leading: const Icon(Icons.child_care),
                title: Text(c.name.isEmpty ? 'Your child' : c.name),
                subtitle: Text(c.role == 'guardian' ? 'You are a guardian' : 'Your role: ${inviteRoleWords(c.role)}'),
              ),
              if (c.role == 'guardian')
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: TextButton.icon(
                    key: Key('invite_${c.id}'),
                    onPressed: () =>
                        _go(InviteGrownUpScreen(service: widget.service, childId: c.id, childName: c.name)),
                    icon: const Icon(Icons.person_add_alt_outlined),
                    label: const Text('Invite a grown-up'),
                  ),
                ),
            ]),
          ),
      ],
      if (s.waitingForYou.isNotEmpty) ...<Widget>[
        Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('Waiting for your yes', style: theme.textTheme.titleMedium)),
        for (final InviteView i in s.waitingForYou)
          Card(
            key: Key('waiting_${i.id}'),
            child: ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: Text(i.statusLine()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go(ConfirmGrownUpScreen(service: widget.service, invite: i)),
            ),
          ),
      ],
      if (s.invites.any((InviteView i) => i.state != InviteState.waitingForYou)) ...<Widget>[
        Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('Invites you sent', style: theme.textTheme.titleMedium)),
        for (final InviteView i in s.invites.where((InviteView i) => i.state != InviteState.waitingForYou))
          _SentInviteCard(
            invite: i,
            busy: _busy,
            onCancel: () => _act(() => widget.service.cancelInvite(i.id), AccountAction.cancelInvite),
            onTurnAway: () => _act(() => widget.service.turnAwayInvite(i.id), AccountAction.turnAwayInvite),
          ),
      ],
      const SizedBox(height: 16),
      _Tile(
        key: const Key('tileSignInCheck'),
        icon: Icons.login,
        title: 'Check this phone’s sign-in',
        subtitle: 'See that it still works, or sign in again.',
        onTap: () => _go(SignInScreen(
            service: widget.service, baseUrl: widget.baseUrl, onCodeRedeemed: widget.onCodeRedeemed)),
      ),
      _Tile(
        key: const Key('tileSignOut'),
        icon: Icons.logout,
        title: 'Sign out of this account',
        subtitle: 'Keeps everything on this phone.',
        onTap: _busy ? () {} : _signOut,
      ),
    ];
  }

  Widget _waitingCard() => Card(
        key: const Key('waitingForInviter'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text("You've asked to join a family. The grown-up who invited you has to say yes, with their PIN, "
                'before you can see anything.'),
            const SizedBox(height: 8),
            FilledButton(
                key: const Key('checkJoin'),
                onPressed: _busy ? null : _checkJoin,
                child: const Text('Check if they have said yes')),
          ]),
        ),
      );

  Future<void> _act(Future<void> Function() f, AccountAction a) async {
    final bool? ok = await _guarded<bool>(() async {
      await f();
      return true;
    },
        action: a,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (ok == true) unawaited(_reload());
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class _SentInviteCard extends StatelessWidget {
  const _SentInviteCard({required this.invite, required this.busy, required this.onCancel, required this.onTurnAway});
  final InviteView invite;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onTurnAway;

  @override
  Widget build(BuildContext context) => Card(
        key: Key('sent_${invite.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${invite.label.isEmpty ? 'Invite' : invite.label} • ${inviteRoleWords(invite.role).split(' (').first}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(invite.statusLine()),
            if (invite.actions.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: <Widget>[
                  if (invite.actions.contains(InviteAction.cancel))
                    TextButton(
                        key: Key('cancel_${invite.id}'),
                        onPressed: busy ? null : onCancel,
                        child: const Text('Cancel this invite')),
                  if (invite.actions.contains(InviteAction.turnAway))
                    TextButton(
                        key: Key('turnaway_${invite.id}'),
                        onPressed: busy ? null : onTurnAway,
                        child: const Text('Turn away')),
                ]),
              ),
          ]),
        ),
      );
}

// ---- make an account -----------------------------------------------------------------------------

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, required this.service, this.suggestedName, this.suggestedZone});
  final FamilyAccountService service;
  final String? suggestedName;
  final String? suggestedZone;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final TextEditingController _code = TextEditingController();
  late final TextEditingController _name = TextEditingController(text: widget.suggestedName ?? '');
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _pin2 = TextEditingController();
  late String? _zone = accountTimeZones.any((HomeZone z) => z.id == widget.suggestedZone) ? widget.suggestedZone : null;
  bool _busy = false;
  AccountProblem? _problem;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (cleanAllowanceCode(_code.text) == null) {
      return setState(() => _problem = const AccountProblem(
          'Enter the invite code you were given. It is long, and has no spaces.', ProblemKind.fixInput));
    }
    if (cleanPersonName(_name.text, kAdultNameMax) == null) {
      return setState(() => _problem = const AccountProblem('Please enter your name.', ProblemKind.fixInput));
    }
    if (_zone == null) {
      return setState(() => _problem = const AccountProblem('Choose the time zone where you live.', ProblemKind.fixInput));
    }
    final String? pinProblem = problemForNewPin(_pin.text);
    if (pinProblem != null) return setState(() => _problem = AccountProblem(pinProblem, ProblemKind.fixInput));
    if (_pin.text != _pin2.text) {
      return setState(() => _problem = const AccountProblem("The two PINs don't match.", ProblemKind.fixInput));
    }
    final String pin = _pin.text;
    final bool? ok = await _guarded<bool>(() async {
      await widget.service.signUp(
          allowanceCode: _code.text, displayName: _name.text, homeTz: _zone!, pin: pin);
      return true;
    },
        action: AccountAction.signUp,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    // The PIN is not kept on screen once sent.
    _pin.clear();
    _pin2.clear();
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Make an account',
        children: <Widget>[
          const _Note('To make an account you need an invite code from whoever runs your Olive server. It is used once. '
              'Nothing from this phone is sent until you press the button.'),
          _ProblemBox(_problem),
          _TextBox(key: const Key('allowanceCode'), controller: _code, label: 'Invite code', enabled: !_busy),
          _TextBox(key: const Key('accountName'), controller: _name, label: 'Your name', enabled: !_busy, maxLength: kAdultNameMax),
          _ZonePicker(
              key: const Key('accountZone'),
              value: _zone,
              label: 'Where you live (time zone)',
              enabled: !_busy,
              onChanged: (String? v) => setState(() => _zone = v)),
          const _Note('Choose a PIN for the account (4 to 8 digits). It is asked for when you add a child or say yes to '
              'another grown-up. It is not the PIN for this phone.'),
          _PinBox(key: const Key('accountPin'), controller: _pin, label: 'PIN', enabled: !_busy),
          _PinBox(key: const Key('accountPin2'), controller: _pin2, label: 'PIN again', enabled: !_busy),
          FilledButton(
              key: const Key('submitCreateAccount'),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Making your account…' : 'Make my account')),
        ],
      );
}

// ---- sign in ----------------------------------------------------------------------------------------

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.service, this.baseUrl = '', this.onCodeRedeemed});
  final FamilyAccountService service;
  final String baseUrl;
  final Future<void> Function(Map<String, dynamic> result)? onCodeRedeemed;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  AccountSnapshot? _snap;
  bool _busy = false;
  AccountProblem? _problem;
  String? _result;

  @override
  void initState() {
    super.initState();
    unawaited(widget.service.snapshot().then((AccountSnapshot s) {
      if (mounted) setState(() => _snap = s);
    }));
  }

  Future<void> _check() async {
    final bool? ok = await _guarded<bool>(widget.service.checkSignIn,
        action: AccountAction.signIn,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (ok == null || !mounted) return;
    setState(() => _result = ok
        ? 'Yes, this phone is signed in and it works.'
        : 'This phone has been removed from the account, or the account was closed. To sign in again, use a code from '
            'a phone that is still signed in.');
  }

  @override
  Widget build(BuildContext context) {
    final AccountSnapshot? s = _snap;
    return _Page(title: 'Sign in', children: <Widget>[
      _ProblemBox(_problem),
      if (_result != null) _Note(_result!, key: const Key('signInResult')),
      if (s != null && s.signedIn) ...<Widget>[
        const _Note('This phone is signed in to an account. It signs itself in again whenever it needs to, so you '
            'rarely have to do anything.'),
        FilledButton(
            key: const Key('checkSignIn'),
            onPressed: _busy ? null : _check,
            child: Text(_busy ? 'Checking…' : 'Check that it still works')),
      ] else if (s != null) ...<Widget>[
        const _Note('To sign in on this phone, open Olive on a phone of yours that is already signed in, go to Settings, '
            'then Family, and use the row that makes a code for a device. Choose My own other device. You get a short '
            'code. Enter it here.'),
        const _Note('If no phone is signed in any more, Olive cannot sign you back in by itself. Ask whoever runs your '
            'server for help.'),
        FilledButton(
            key: const Key('enterSignInCode'),
            onPressed: widget.baseUrl.isEmpty
                ? null
                : () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
                    builder: (BuildContext rc) => PairingRedeemScreen(
                          baseUrl: widget.baseUrl,
                          role: 'guardian',
                          localFirst: true,
                          onNotNow: () => Navigator.of(rc).pop(),
                          onRedeemed: (Map<String, dynamic> r) => unawaited(_redeemed(r)),
                        ))),
            child: const Text('Enter a code')),
      ],
    ]);
  }

  Future<void> _redeemed(Map<String, dynamic> r) async {
    try {
      await widget.onCodeRedeemed?.call(r);
    } catch (e) {
      if (mounted) setState(() => _problem = problemFor(e, AccountAction.signIn));
    }
  }
}

// ---- add a child ---------------------------------------------------------------------------------

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key, required this.service, this.suggestedName, this.suggestedZone, this.localAge, this.now});
  final FamilyAccountService service;
  final String? suggestedName;
  final String? suggestedZone;

  /// The age already set for her on this phone, to point out a mismatch with the date.
  final int? localAge;
  final DateTime Function()? now;

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.suggestedName ?? '');
  final TextEditingController _pin = TextEditingController();
  late String? _zone = accountTimeZones.any((HomeZone z) => z.id == widget.suggestedZone) ? widget.suggestedZone : null;
  DateTime? _birth;
  bool _busy = false;
  AccountProblem? _problem;

  DateTime get _today => (widget.now ?? DateTime.now)();

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime today = _today;
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(today.year - 6, today.month, today.day),
      firstDate: DateTime(today.year - (kMaxChildAgeYears + 1), today.month, today.day).add(const Duration(days: 1)),
      lastDate: today,
      helpText: 'Her birth date',
    );
    if (d != null && mounted) setState(() => _birth = d);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (cleanPersonName(_name.text, kChildNameMax) == null) {
      return setState(() => _problem = const AccountProblem('Please enter her first name.', ProblemKind.fixInput));
    }
    final String? dp = problemForBirthDate(_birth, _today);
    if (dp != null) return setState(() => _problem = AccountProblem(dp, ProblemKind.fixInput));
    if (_zone == null) {
      return setState(() => _problem = const AccountProblem('Choose the time zone where she lives.', ProblemKind.fixInput));
    }
    if (!looksLikePin(_pin.text)) {
      return setState(() => _problem = const AccountProblem('Enter your account PIN. It is 4 to 8 digits.', ProblemKind.fixInput));
    }
    final String pin = _pin.text;
    final bool? ok = await _guarded<bool>(() async {
      await widget.service.addChild(displayName: _name.text, birthDate: _birth!, homeTz: _zone!, pin: pin);
      return true;
    },
        action: AccountAction.addChild,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _pin.clear();
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final String? mismatch = ageMismatchNote(_birth, widget.localAge, _today);
    return _Page(title: 'Add your child', children: <Widget>[
      const _Note('This puts her on your account and makes you her guardian. It does not change anything in her app on '
          'this phone.'),
      _ProblemBox(_problem),
      _TextBox(key: const Key('childName'), controller: _name, label: 'Her first name', enabled: !_busy, maxLength: kChildNameMax),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          key: const Key('pickBirthDate'),
          onPressed: _busy ? null : _pickDate,
          icon: const Icon(Icons.cake_outlined),
          label: Text(_birth == null ? 'Choose her birth date' : 'Born ${_dateWords(_birth!)}'),
        ),
      ),
      if (mismatch != null) _Note(mismatch, key: const Key('ageMismatch')),
      _ZonePicker(
          key: const Key('childZone'),
          value: _zone,
          label: 'Where she lives (time zone)',
          enabled: !_busy,
          onChanged: (String? v) => setState(() => _zone = v)),
      const _Note('Type your account PIN to confirm it is you.'),
      _PinBox(key: const Key('childPin'), controller: _pin, label: 'Your account PIN', enabled: !_busy),
      FilledButton(
          key: const Key('submitAddChild'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Adding…' : 'Add her')),
    ]);
  }
}

// ---- invite another grown-up ---------------------------------------------------------------------

class InviteGrownUpScreen extends StatefulWidget {
  const InviteGrownUpScreen({super.key, required this.service, required this.childId, required this.childName});
  final FamilyAccountService service;
  final String childId;
  final String childName;

  @override
  State<InviteGrownUpScreen> createState() => _InviteGrownUpScreenState();
}

class _InviteGrownUpScreenState extends State<InviteGrownUpScreen> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  String _role = kInvitableRoles.first;
  bool _busy = false;
  AccountProblem? _problem;
  CreatedInvite? _made;
  bool _copied = false;

  @override
  void dispose() {
    _label.dispose();
    _email.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (cleanPersonName(_label.text, kInviteLabelMax) == null) {
      return setState(() => _problem = AccountProblem(
          'Add the word ${_childWord()} will use for them, such as Nana.', ProblemKind.fixInput));
    }
    if (cleanEmail(_email.text) == null) {
      return setState(() => _problem = const AccountProblem(
          'Enter the email address the invite is for, like name@example.com.', ProblemKind.fixInput));
    }
    if (!looksLikePin(_pin.text)) {
      return setState(() => _problem = const AccountProblem('Enter your account PIN. It is 4 to 8 digits.', ProblemKind.fixInput));
    }
    final String pin = _pin.text;
    final CreatedInvite? made = await _guarded<CreatedInvite>(
        () => widget.service.createInvite(
            childId: widget.childId, role: _role, label: _label.text, email: _email.text, pin: pin),
        action: AccountAction.createInvite,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _pin.clear();
    if (made != null && mounted) setState(() => _made = made);
  }

  String _childWord() => widget.childName.isEmpty ? 'your child' : widget.childName;

  @override
  Widget build(BuildContext context) {
    final CreatedInvite? made = _made;
    if (made != null) return _madeView(made);
    return _Page(title: 'Invite a grown-up', children: <Widget>[
      _Note('This invites another grown-up into ${_childWord()}’s family. They get nothing until you say yes, '
          'with your PIN, after they have used the invite.'),
      _ProblemBox(_problem),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: const Key('inviteRole'),
          initialValue: _role,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Their role', border: OutlineInputBorder()),
          items: <DropdownMenuItem<String>>[
            for (final String r in kInvitableRoles)
              DropdownMenuItem<String>(value: r, child: Text(inviteRoleWords(r), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _busy ? null : (String? v) => setState(() => _role = v ?? _role),
        ),
      ),
      _TextBox(
          key: const Key('inviteLabel'),
          controller: _label,
          label: 'What will ${_childWord()} call them?',
          hint: 'Nana, Uncle Sam…',
          enabled: !_busy,
          maxLength: kInviteLabelMax),
      _TextBox(
          key: const Key('inviteEmail'),
          controller: _email,
          label: 'Their email address',
          hint: 'The invite only works for this address',
          enabled: !_busy,
          keyboard: TextInputType.emailAddress,
          maxLength: kEmailMax),
      const _Note('Type your account PIN to confirm it is you.'),
      _PinBox(key: const Key('invitePin'), controller: _pin, label: 'Your account PIN', enabled: !_busy),
      FilledButton(
          key: const Key('submitInvite'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Making the invite…' : 'Make the invite')),
    ]);
  }

  Widget _madeView(CreatedInvite made) => _Page(title: 'Invite made', children: <Widget>[
        const _Note('Olive does not send this. Give the code below to them yourself, in person or in a message you '
            'trust. Anyone who has it can use it, so do not post it anywhere.'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              SelectableText(made.code, key: const Key('inviteCode'), style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
              const SizedBox(height: 8),
              Text(made.expiresAt == null ? 'It runs out after a while.' : 'It runs out on ${_dateWords(made.expiresAt!.toLocal())}.'),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('copyInviteCode'),
          onPressed: () async {
            bool ok = true;
            try {
              await Clipboard.setData(ClipboardData(text: made.code));
            } catch (_) {
              ok = false;
            }
            if (mounted) setState(() => _copied = ok);
            if (!ok && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Couldn't copy it. Press and hold the code to select it, then copy it yourself.")));
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(_copied ? 'Copied' : 'Copy the code'),
        ),
        const SizedBox(height: 8),
        const _Note('They open Olive, go to Settings, then Family account, then I was invited, and paste it. When they '
            'have finished, you will see their name on the Family account page and can say yes.'),
        FilledButton(key: const Key('doneInvite'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Done')),
      ]);
}

// ---- I was invited -------------------------------------------------------------------------------

class JoinInviteScreen extends StatefulWidget {
  const JoinInviteScreen({super.key, required this.service, this.resume});
  final FamilyAccountService service;

  /// An invite already opened on this phone and not finished.
  final PendingJoin? resume;

  @override
  State<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

class _JoinInviteScreenState extends State<JoinInviteScreen> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  InviteLookup? _found;
  bool? _signedIn;
  bool _busy = false;
  AccountProblem? _problem;

  @override
  void initState() {
    super.initState();
    final PendingJoin? r = widget.resume;
    if (r != null) _code.text = r.inviteId;
    unawaited(widget.service.snapshot().then((AccountSnapshot s) {
      if (mounted) setState(() => _signedIn = s.signedIn);
    }));
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    final InviteLookup? f = await _guarded<InviteLookup>(() => widget.service.lookUpInvite(_code.text),
        action: AccountAction.lookUpInvite,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (f != null && mounted) setState(() => _found = f);
  }

  Future<void> _join({required bool withMyAccount}) async {
    final InviteLookup f = _found!;
    if (!withMyAccount && cleanPersonName(_name.text, kAdultNameMax) == null) {
      return setState(() => _problem = const AccountProblem('Please enter your name.', ProblemKind.fixInput));
    }
    final bool? ok = await _guarded<bool>(() async {
      if (withMyAccount) {
        await widget.service.useInviteWithAccount(f.id);
      } else {
        await widget.service.joinAsNew(inviteCode: f.id, displayName: _name.text);
      }
      return true;
    },
        action: withMyAccount ? AccountAction.useInviteWithAccount : AccountAction.joinInvite,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final InviteLookup? f = _found;
    return _Page(title: 'I was invited', children: <Widget>[
      _ProblemBox(_problem),
      if (f == null) ...<Widget>[
        const _Note('Another grown-up sent you an invite code. Paste it here. Nothing is decided until you say so.'),
        _TextBox(key: const Key('inviteCodeIn'), controller: _code, label: 'Invite code', enabled: !_busy),
        FilledButton(
            key: const Key('lookUpInvite'),
            onPressed: _busy ? null : _look,
            child: Text(_busy ? 'Looking…' : 'Look up this invite')),
      ] else ...<Widget>[
        Card(
          key: const Key('inviteFound'),
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text('You are invited as ${inviteRoleWords(f.role).split(' (').first.toLowerCase()}'),
            subtitle: Text('They will be called ${f.label.isEmpty ? 'by a name they chose' : f.label}. Sent to '
                '${f.maskedEmail}.'),
          ),
        ),
        const SizedBox(height: 8),
        const _Note('The grown-up who invited you has to say yes, with their PIN, before you can see anything of the '
            'family.'),
        if (_signedIn == true) ...<Widget>[
          const _Note('This phone is signed in to an account. You can use that account for this invite, if the invite was '
              'sent to its email address.'),
          FilledButton(
              key: const Key('useMyAccount'),
              onPressed: _busy ? null : () => _join(withMyAccount: true),
              child: Text(_busy ? 'Working…' : 'Use my account')),
        ] else ...<Widget>[
          _TextBox(key: const Key('joinName'), controller: _name, label: 'Your name', enabled: !_busy, maxLength: kAdultNameMax),
          FilledButton(
              key: const Key('joinAsNew'),
              onPressed: _busy ? null : () => _join(withMyAccount: false),
              child: Text(_busy ? 'Joining…' : 'Make my account and ask to join')),
        ],
      ],
    ]);
  }
}

// ---- the inviter's yes ------------------------------------------------------------------------------

class ConfirmGrownUpScreen extends StatefulWidget {
  const ConfirmGrownUpScreen({super.key, required this.service, required this.invite});
  final FamilyAccountService service;
  final InviteView invite;

  @override
  State<ConfirmGrownUpScreen> createState() => _ConfirmGrownUpScreenState();
}

class _ConfirmGrownUpScreenState extends State<ConfirmGrownUpScreen> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  AccountProblem? _problem;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (!looksLikePin(_pin.text)) {
      return setState(() => _problem = const AccountProblem('Enter your account PIN. It is 4 to 8 digits.', ProblemKind.fixInput));
    }
    final String pin = _pin.text;
    final bool? ok = await _guarded<bool>(() async {
      await widget.service.confirmInvite(widget.invite.id, pin);
      return true;
    },
        action: AccountAction.confirmInvite,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _pin.clear();
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _turnAway() async {
    final bool? ok = await _guarded<bool>(() async {
      await widget.service.turnAwayInvite(widget.invite.id);
      return true;
    },
        action: AccountAction.turnAwayInvite,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final InviteView i = widget.invite;
    final String who = (i.claimantName ?? '').trim().isEmpty ? 'Someone' : i.claimantName!.trim();
    return _Page(title: 'Say yes or no', children: <Widget>[
      Card(
        child: ListTile(
          leading: const Icon(Icons.how_to_reg_outlined),
          title: Text('$who asked to join as ${inviteRoleWords(i.role).split(' (').first.toLowerCase()}'),
          subtitle: Text('You invited ${maskEmail(i.invitedEmail)}. Say yes only if $who is the person you meant.'),
        ),
      ),
      const SizedBox(height: 8),
      const _Note('If you say yes, they can see what a grown-up in this family sees. If anything feels wrong, turn '
          'them away; you can always send a new invite.'),
      _ProblemBox(_problem),
      _PinBox(key: const Key('confirmPin'), controller: _pin, label: 'Your account PIN', enabled: !_busy),
      FilledButton(
          key: const Key('submitConfirm'),
          onPressed: _busy ? null : _confirm,
          child: Text(_busy ? 'Saying yes…' : 'Yes, add them')),
      const SizedBox(height: 8),
      OutlinedButton(key: const Key('submitTurnAway'), onPressed: _busy ? null : _turnAway, child: const Text('No, turn them away')),
    ]);
  }
}

// ---- the account's own PIN ------------------------------------------------------------------------

class SetAccountPinScreen extends StatefulWidget {
  const SetAccountPinScreen({super.key, required this.service});
  final FamilyAccountService service;

  @override
  State<SetAccountPinScreen> createState() => _SetAccountPinScreenState();
}

class _SetAccountPinScreenState extends State<SetAccountPinScreen> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _pin2 = TextEditingController();
  bool _busy = false;
  AccountProblem? _problem;

  @override
  void dispose() {
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String? p = problemForNewPin(_pin.text);
    if (p != null) return setState(() => _problem = AccountProblem(p, ProblemKind.fixInput));
    if (_pin.text != _pin2.text) {
      return setState(() => _problem = const AccountProblem("The two PINs don't match.", ProblemKind.fixInput));
    }
    final String pin = _pin.text;
    final bool? ok = await _guarded<bool>(() async {
      await widget.service.setFirstPin(pin);
      return true;
    },
        action: AccountAction.setPin,
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? pr) => setState(() => _problem = pr));
    _pin.clear();
    _pin2.clear();
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Set your account PIN', children: <Widget>[
        const _Note('This PIN is asked for when you add a child or say yes to another grown-up. It is not the PIN for '
            'this phone, and Olive cannot tell you what it is if you forget it.'),
        _ProblemBox(_problem),
        _PinBox(key: const Key('newPin'), controller: _pin, label: 'PIN (4 to 8 digits)', enabled: !_busy),
        _PinBox(key: const Key('newPin2'), controller: _pin2, label: 'PIN again', enabled: !_busy),
        FilledButton(
            key: const Key('submitSetPin'),
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Saving…' : 'Save my PIN')),
      ]);
}
