@IsTest
private class HarnessReleaseHealthTest {
    @IsTest
    static void checkReturnsReleaseStatus() {
        Test.startTest();
        HarnessReleaseHealth.Status status = HarnessReleaseHealth.check();
        Test.stopTest();

        System.assertEquals(true, status.ready, 'The release health endpoint should report ready.');
        System.assertEquals('harness-governed', status.releaseChannel, 'The release channel should identify Harness governance.');
        System.assertNotEquals(null, status.checkedAt, 'The health check should include a timestamp.');
    }
}
