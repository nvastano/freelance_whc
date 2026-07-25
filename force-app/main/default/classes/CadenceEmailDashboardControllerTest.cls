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

    @isTest
    static void testGetDrillDownRecordsWithNullInputsReturnsEmpty() {
        Test.startTest();
        List<CadenceEmailDashboardController.DrillDownRecord> result =
            CadenceEmailDashboardController.getDrillDownRecords(null, null, null, 'opened', null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Null inputs should return an empty list');
    }

    @isTest
    static void testDrillDownRecordSortOrder() {
        CadenceEmailDashboardController.DrillDownRecord older = new CadenceEmailDashboardController.DrillDownRecord();
        older.sentDate = DateTime.newInstance(2024, 6, 1, 0, 0, 0);
        older.contactName = 'Alice';
        older.repName = 'Rep1';
        older.sourceType = 'Manual';
        older.isOpened = false;
        older.isClicked = false;
        older.isBounced = false;
        older.hasReply = false;

        CadenceEmailDashboardController.DrillDownRecord newer = new CadenceEmailDashboardController.DrillDownRecord();
        newer.sentDate = DateTime.newInstance(2024, 7, 1, 0, 0, 0);
        newer.contactName = 'Bob';
        newer.repName = 'Rep2';
        newer.sourceType = 'Automated';
        newer.isOpened = true;
        newer.isClicked = false;
        newer.isBounced = false;
        newer.hasReply = false;

        CadenceEmailDashboardController.DrillDownRecord noDate = new CadenceEmailDashboardController.DrillDownRecord();
        noDate.sentDate = null;
        noDate.contactName = 'Charlie';
        noDate.repName = 'Rep3';
        noDate.sourceType = 'Manual';
        noDate.isOpened = false;
        noDate.isClicked = false;
        noDate.isBounced = false;
        noDate.hasReply = false;

        CadenceEmailDashboardController.DrillDownRecord sameAsOlder = new CadenceEmailDashboardController.DrillDownRecord();
        sameAsOlder.sentDate = DateTime.newInstance(2024, 6, 1, 0, 0, 0);
        sameAsOlder.contactName = 'Dana';
        sameAsOlder.repName = 'Rep4';
        sameAsOlder.sourceType = 'Manual';
        sameAsOlder.isOpened = false;
        sameAsOlder.isClicked = false;
        sameAsOlder.isBounced = false;
        sameAsOlder.hasReply = false;

        List<CadenceEmailDashboardController.DrillDownRecord> recs =
            new List<CadenceEmailDashboardController.DrillDownRecord>{ older, noDate, newer, sameAsOlder };

        Test.startTest();
        recs.sort();
        Test.stopTest();

        System.assertEquals('Bob', recs[0].contactName, 'Most recent sentDate should sort first (DESC)');
        System.assertEquals('Charlie', recs[recs.size() - 1].contactName, 'Null sentDate should sort last');
    }

    @isTest(SeeAllData=true)
    static void testGetDrillDownRecordsForRealCadences() {
        List<AggregateResult> topCadences = [
            SELECT ActionCadenceId cadenceId, COUNT(Id) cnt
            FROM ActionCadenceStepTracker
            WHERE ActionCadenceId != null
            GROUP BY ActionCadenceId
            ORDER BY COUNT(Id) DESC
            LIMIT 2
        ];
        if (topCadences.isEmpty()) {
            return;
        }

        Id cadenceId = (Id) topCadences[0].get('cadenceId');
        Date startD = Date.newInstance(2020, 1, 1);
        Date endD = Date.today();

        Test.startTest();
        for (String filterType : new List<String>{ 'sent', 'delivered', 'opened', 'clicked', 'bounced', 'replied' }) {
            List<CadenceEmailDashboardController.DrillDownRecord> result =
                CadenceEmailDashboardController.getDrillDownRecords(cadenceId, startD, endD, filterType, null);
            System.assertNotEquals(null, result, filterType + ' filter should return a non-null list');
            for (CadenceEmailDashboardController.DrillDownRecord rec : result) {
                System.assertNotEquals(null, rec.contactName, 'contactName should never be null');
                System.assertNotEquals(null, rec.repName, 'repName should never be null');
                System.assertNotEquals(null, rec.sourceType, 'sourceType should never be null');
                System.assert(rec.sourceType == 'Manual' || rec.sourceType == 'Automated',
                    'sourceType must be Manual or Automated');
            }
        }

        List<AggregateResult> repQuery = [
            SELECT CreatedById repId
            FROM EmailMessage
            WHERE ActionCadenceStepTracker.ActionCadenceId = :cadenceId
              AND MessageDate >= LAST_N_YEARS:3
            GROUP BY CreatedById
            LIMIT 1
        ];
        if (!repQuery.isEmpty()) {
            Id repId = (Id) repQuery[0].get('repId');
            List<CadenceEmailDashboardController.DrillDownRecord> repResult =
                CadenceEmailDashboardController.getDrillDownRecords(cadenceId, startD, endD, 'rep', repId);
            System.assertNotEquals(null, repResult, 'Rep filter should return a non-null list');
        }
        Test.stopTest();
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
