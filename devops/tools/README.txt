1) Apply repo-root patch (if needed):
   patch -p0 < fix-repo-root.patch

2) Ensure build script executable:
   chmod +x build_final_zip.sh build_aiagent_bundle.sh

3) Build ZIP locally:
   ./build_final_zip.sh

4) Run self-test:
   chmod +x devops/tools/self_test_bundle.sh
   ./devops/tools/self_test_bundle.sh aiagent_release_YYYYMMDD_HHMM.zip

5) Deploy from ZIP to server:
   sudo ./devops/tools/deploy_from_zip.sh aiagent_release_...zip --target /opt/aiagent --non-interactive

