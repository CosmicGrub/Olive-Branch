/**
 * The flavor guard (tools/check-flavors.mjs): the real tree is clean, and each way the direct / play split can quietly break is
 * caught: the install permission leaking into src/main or the play flavor, an applicationId suffix that would stop an in-place
 * update, the release-signing refusal no longer matching flavored task names, installer code in the shared source set, a missing
 * default flavor, CI compiling or launching only one flavor.
 *
 * usage: node tools/test/check_flavors.test.mjs
 */
import { flavorProblems, readTree } from '../check-flavors.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };

const real = readTree();
const fresh = () => JSON.parse(JSON.stringify(real));
const problems = (f) => flavorProblems(f);
const has = (f, re) => problems(f).some((p) => re.test(p));
const g = 'flavors';

check(g, 'the real tree has no flavor problems', problems(real), []);

{
  const f = fresh(); f.manifests.main = f.manifests.main.replace('<uses-permission android:name="android.permission.CAMERA"/>', '<uses-permission android:name="android.permission.CAMERA"/>\n<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>');
  check(g, 'the install permission declared in src/main (so in play) is caught', has(f, /src\/main\/AndroidManifest\.xml mentions REQUEST_INSTALL_PACKAGES/), true);
}
{
  const f = fresh(); f.manifests.main = f.manifests.main.replace('<application', '<!-- REQUEST_INSTALL_PACKAGES is only mentioned here -->\n<application');
  check(g, 'a COMMENT that mentions the permission is not a declaration', problems(f), []);
}
{
  const f = fresh(); f.manifests.play = f.manifests.play.replace(/<uses-permission[^>]*\/>/, '');
  check(g, 'a play manifest that no longer removes the permission is caught', has(f, /must REMOVE REQUEST_INSTALL_PACKAGES/), true);
}
{
  const f = fresh(); f.manifests.play = f.manifests.play.replace(' tools:node="remove"', '');
  check(g, 'a play manifest that DECLARES it (no remove) is caught', has(f, /must REMOVE/), true);
}
{
  const f = fresh(); f.manifests.play = f.manifests.play.replace('xmlns:tools="http://schemas.android.com/tools"', '');
  check(g, 'a play manifest without the tools namespace is caught', has(f, /tools namespace/), true);
}
{
  const f = fresh(); f.manifests.direct = f.manifests.direct.replace(/<uses-permission[^>]*\/>/, '');
  check(g, 'a direct manifest without the permission is caught (the installer could never run)', has(f, /must DECLARE/), true);
}
{
  const f = fresh(); delete f.manifests.direct;
  check(g, 'a missing direct manifest is caught', has(f, /src\/direct\/AndroidManifest\.xml is missing/), true);
}
{
  const f = fresh(); f.manifests.debug = '<manifest><uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/></manifest>';
  check(g, 'the permission in the debug source set is caught', has(f, /src\/debug/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('create("direct") { dimension = "distribution" }', 'create("direct") { dimension = "distribution"; applicationIdSuffix = ".direct" }');
  check(g, 'an applicationIdSuffix on a flavor is caught (it would stop in-place updates)', has(f, /applicationIdSuffix/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('create("play") { dimension = "distribution" }', 'create("play") { dimension = "distribution"; versionNameSuffix = "-play" }');
  check(g, 'a versionNameSuffix on a flavor is caught', has(f, /versionNameSuffix/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('create("play")', 'create("store")');
  check(g, 'a renamed flavor is caught', has(f, /exactly "direct" and "play"/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('        create("play") { dimension = "distribution" }\n', '').replace('        create("play") { dimension = "distribution" }\r\n', '');
  check(g, 'a missing play flavor is caught', has(f, /exactly "direct" and "play"/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('flavorDimensions.add("distribution")', 'flavorDimensions.add("distribution")\n    flavorDimensions.add("tier")');
  check(g, 'a second flavor dimension is caught', has(f, /exactly one flavorDimensions/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('Regex("^(assemble|bundle|package)(Direct|Play)?Release\\$")', 'Regex("^(assemble|bundle|package)Release\\$")');
  check(g, 'a release-signing guard that no longer matches flavored tasks is caught', has(f, /does not match the task assembleDirectRelease/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('Regex("^(assemble|bundle|package)(Direct|Play)?Release\\$")', 'Regex("Release")');
  check(g, 'a guard so broad it would refuse debug and compile tasks is caught', has(f, /must never be refused/), true);
}
{
  const f = fresh(); f.gradle = f.gradle.replace('releasePackagingTask.matches(it.name)', 'it.name in setOf("assembleRelease")');
  check(g, 'the old name-list guard coming back is caught', has(f, /no longer uses releasePackagingTask/), true);
}
{
  const f = fresh(); f.code['src/main/kotlin/x/Installer.kt'] = 'import android.content.pm.PackageInstaller\nclass Installer { val i = PackageInstaller.SessionParams(1) }';
  check(g, 'installer code in the shared source set (so in play) is caught', has(f, /Installer\.kt uses the package-install API/), true);
}
{
  const f = fresh(); f.code['src/play/kotlin/x/Stub.kt'] = 'class Stub { fun x() = canRequestPackageInstalls() }';
  check(g, 'canRequestPackageInstalls in the play source set is caught', has(f, /Stub\.kt/), true);
}
{
  const f = fresh(); f.code['src/main/kotlin/x/Apk.kt'] = 'val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")';
  check(g, 'an ACTION_VIEW on an apk mime type in shared code is caught', has(f, /Apk\.kt/), true);
}
{
  const f = fresh(); f.code['src/main/kotlin/x/Doc.kt'] = '// we never use PackageInstaller here\nclass Doc';
  check(g, 'a comment that names PackageInstaller is not a use', problems(f), []);
}
{
  const f = fresh(); f.pubspec = f.pubspec.replace('default-flavor: direct', '# default-flavor: direct');
  check(g, 'a missing default flavor is caught (a plain flutter build would fail)', has(f, /default-flavor: direct/), true);
}
{
  const f = fresh(); f.pubspec = f.pubspec.replace('default-flavor: direct', 'default-flavor: play');
  check(g, 'a default flavor of play is caught', has(f, /default-flavor: direct/), true);
}
{
  const f = fresh(); f.verify = f.verify.replace(':app:compilePlayDebugKotlin', '');
  check(g, 'CI compiling only the direct flavor is caught', has(f, /compilePlayDebugKotlin/), true);
}
{
  const f = fresh(); f.verify = `${f.verify}\n./gradlew :app:compileDebugKotlin\n`;
  check(g, 'a leftover :app:compileDebugKotlin (no such task with flavors) is caught', has(f, /still names :app:compileDebugKotlin/), true);
}
{
  const f = fresh(); f.smoke = f.smoke.replace(/^\s+flavor: play\s*$/gm, '            flavor: direct');
  check(g, 'a smoke matrix that never launches the play flavor is caught', has(f, /BOTH flavors/), true);
}
{
  const f = fresh(); f.smoke = f.smoke.replace('--flavor ${{ matrix.flavor }}', '');
  check(g, 'a smoke build with no --flavor is caught', has(f, /--flavor/), true);
}
{
  const f = fresh(); f.smoke = f.smoke.replace('app-${{ matrix.flavor }}-release.apk', 'app-release.apk');
  check(g, 'a smoke step that copies the un-flavored file name is caught', has(f, /app-<flavor>-release\.apk/), true);
}
{
  const f = fresh(); f.gradle = 'android { }';
  check(g, 'a gradle file with no readable flavors block fails closed', has(f, /no android \{ productFlavors/), true);
}

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
