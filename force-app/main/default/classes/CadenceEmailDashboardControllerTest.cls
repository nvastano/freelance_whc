@isTest
private class CadenceEmailDashboardControllerTest {

    @isTest
    static void testGetDashboardDataWithNullInputsReturnsEmptyStructure() {
        Test.startTest();
        CadenceEmailDashboardController.DashboardData data = CadenceEmailDashboardController.getDashboardData(null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, data, 'Expected a non-null DashboardData shell when inputs are missing');
        System.assertEquals(0, data.overview.sent, 'Sent should default to 0 without valid inputs');
        System.assertEquals(0, data.byRep.size(), 'By-rep list should be empty without valid inputs');
        System.assertEquals(0, data.opensOverTime.size(), 'Opens-over-time should be empty without valid inputs');
        System.assertEquals(0, data.clickedContacts.size(), 'Clicked contacts should be empty without valid inputs');
    }

    // ActionCadence / ActionCadenceStep / their tracker objects are managed exclusively through the
    // Sales Engagement Cadence Builder and are not DML-createable (createable=false on all four),
    // so they cannot be faked with isolated test data. These tests validate structural invariants
    // against the org's real, currently-active cadences instead of exact hardcoded counts, since the
    // underlying data will keep changing as cadences run.
    @isTest(SeeAllData=true)
    static void testGetCadenceOptionsReturnsActiveCadences() {
        Test.startTest();
        List<CadenceEmailDashboardController.CadenceOption> options = CadenceEmailDashboardController.getCadenceOptions();
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected at least one active cadence in the org');
        for (CadenceEmailDashboardController.CadenceOption opt : options) {
            System.assertNotEquals(null, opt.cadenceId, 'Cadence option should have an Id');
            System.assertNotEquals(null, opt.name, 'Cadence option should have a name');
            System.assertNotEquals(null, opt.folderName, 'Cadence option should always have a folder name (defaults to Uncategorized)');
        }
    }

    @isTest(SeeAllData=true)
    static void testGetDashboardDataForRealCadencesReturnsConsistentStructure() {
        // Pick the cadences with the most tracker activity (rather than an arbitrary alphabetical
        // slice) so this test actually exercises the email/engagement branches below instead of
        // hitting cadences with zero linked send history.
        List<AggregateResult> topCadences = [
            SELECT ActionCadenceId cadenceId, COUNT(Id) cnt
            FROM ActionCadenceStepTracker
            WHERE ActionCadenceId != null
            GROUP BY ActionCadenceId
            ORDER BY COUNT(Id) DESC
            LIMIT 5
        ];
        if (topCadences.isEmpty()) {
            return; // nothing active to validate against in this org snapshot
        }

        Test.startTest();
        for (AggregateResult ar : topCadences) {
            Id cadenceId = (Id) ar.get('cadenceId');
            CadenceEmailDashboardController.DashboardData data = CadenceEmailDashboardController.getDashboardData(
                cadenceId, Date.newInstance(2020, 1, 1), Date.today()
            );

            System.assertNotEquals(null, data.overview, 'Overview metrics should always be populated');
            System.assert(data.overview.sent >= 0, 'Sent should never be negative');
            System.assert(data.overview.opened <= data.overview.sent, 'Opened can never exceed sent');
            System.assert(data.overview.clicked <= data.overview.sent, 'Clicked can never exceed sent');
            System.assert(data.overview.bounced <= data.overview.sent, 'Bounced can never exceed sent');
            System.assert(data.overview.openRate >= 0 && data.overview.openRate <= 100, 'Open rate should be a valid percentage');
            System.assert(data.overview.clickRate >= 0 && data.overview.clickRate <= 100, 'Click rate should be a valid percentage');

            for (CadenceEmailDashboardController.RepMetrics rep : data.byRep) {
                System.assert(rep.sent >= rep.opened, 'A rep cannot have more opens than sends');
                System.assert(rep.sent >= rep.clicked, 'A rep cannot have more clicks than sends');
            }
            for (CadenceEmailDashboardController.ClickedContact cc : data.clickedContacts) {
                System.assertNotEquals(null, cc.contactName, 'Clicked contact rows should always have a name');
            }

            for (CadenceEmailDashboardController.DayCount dc : data.opensOverTime) {
                System.assertNotEquals(null, dc.day, 'Opens-over-time rows should always have a date');
                System.assert(dc.count > 0, 'Opens-over-time rows should never be zero/negative');
            }
        }
        Test.stopTest();
    }
}
