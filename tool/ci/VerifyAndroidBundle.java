import java.io.InputStream;
import java.nio.file.Path;
import java.security.CodeSigner;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Set;
import java.util.jar.JarFile;

/** Verify every AAB entry with the JDK's JAR verifier, not certificate text alone. */
public class VerifyAndroidBundle {
  public static void main(String[] args) throws Exception {
    if (args.length != 3) throw new IllegalArgumentException("aab expected-sha256|- development|distribution");
    boolean distribution = args[2].equals("distribution");
    if (!distribution && !args[2].equals("development")) throw new IllegalArgumentException("Unknown signing mode");
    String expected = args[1].replace(":", "").toLowerCase(Locale.ROOT);
    if (!expected.equals("-") && !expected.matches("[0-9a-f]{64}")) throw new IllegalArgumentException("Invalid expected SHA256");
    if (distribution && expected.equals("-")) throw new IllegalArgumentException("Distribution needs expected upload certificate SHA256");
    Set<String> fingerprints = new HashSet<>();
    int signedEntries = 0;
    try (JarFile jar = new JarFile(Path.of(args[0]).toFile(), true)) {
      if (jar.getManifest() == null || jar.getEntry("BundleConfig.pb") == null
          || jar.getEntry("base/manifest/AndroidManifest.xml") == null) {
        throw new SecurityException("Missing signed bundle structure");
      }
      var entries = jar.entries();
      while (entries.hasMoreElements()) {
        var entry = entries.nextElement();
        String name = entry.getName().toUpperCase(Locale.ROOT);
        if (entry.isDirectory() || name.equals("META-INF/MANIFEST.MF")
            || name.matches("META-INF/[^/]+\\.(SF|RSA|DSA|EC)")) continue;
        // Reading to EOF is essential: it triggers digest and signature checks.
        try (InputStream stream = jar.getInputStream(entry)) {
          stream.transferTo(java.io.OutputStream.nullOutputStream());
        }
        CodeSigner[] signers = entry.getCodeSigners();
        if (signers == null || signers.length != 1) {
          throw new SecurityException("Unsigned or ambiguously signed entry: " + entry.getName());
        }
        X509Certificate certificate = (X509Certificate) signers[0].getSignerCertPath().getCertificates().get(0);
        certificate.checkValidity();
        String fingerprint = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
        if (!expected.equals("-") && !expected.equals(fingerprint)) throw new SecurityException("Wrong AAB upload certificate");
        String subject = (certificate.getSubjectX500Principal().getName() + ",").replace(" ", "").toLowerCase(Locale.ROOT);
        if (distribution && subject.contains("cn=androiddebug,")) throw new SecurityException("Android debug certificate is not distribution signing");
        fingerprints.add(fingerprint);
        signedEntries++;
      }
    }
    if (signedEntries == 0 || fingerprints.size() != 1) throw new SecurityException("Inconsistent or empty signed bundle");
    System.out.println("{\"certificate_sha256\":\"" + fingerprints.iterator().next()
        + "\",\"signed_entries\":" + signedEntries + "}");
  }
}
