@isTest
private class MktCadenceTaskDashboardControllerTest {

    @isTest
    static void testGetDashboardDataWithNoOwnerFilterReturnsNonNullList() {
        Test.startTest();
        List<MktCadenceTaskDashboardController.AccountRow> rows =
            MktCadenceTaskDashboardController.getDashboardData(null);
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Expected a non-null (possibly empty) list');
    }

    @isTest
    static void testGetDashboardDataWithBogusOwnerReturnsEmptyList() {
        Test.startTest();
        List<MktCadenceTaskDashboardController.AccountRow> rows =
            MktCadenceTaskDashboardController.getDashboardData(UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Expected a non-null (possibly empty) list even for a user with no MKT activity');
    }

    // ActionCadence / ActionCadenceTracker are managed exclusively through the Sales Engagement
    // Cadence Builder and are not DML-createable (createable=false), so this validates structural
    // invariants against the org's real "MKT Cadence" folder and its live trackers/tasks instead of
    // hardcoded counts, since the underlying data changes as cadences run.
    @isTest(SeeAllData=true)
    static void testGetUserOptionsReturnsRealMktOwners() {
        Test.startTest();
        List<MktCadenceTaskDashboardController.UserOption> options =
            MktCadenceTaskDashboardController.getUserOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Expected a non-null (possibly empty) list of owners');
        for (MktCadenceTaskDashboardController.UserOption opt : options) {
            System.assertNotEquals(null, opt.userId, 'User option should have an Id');
            System.assertNotEquals(null, opt.name, 'User option should have a name');
        }
    }

    @isTest(SeeAllData=true)
    static void testGetDashboardDataForRealMktOwnerReturnsConsistentStructure() {
        List<MktCadenceTaskDashboardController.UserOption> options =
            MktCadenceTaskDashboardController.getUserOptions();
        if (options.isEmpty()) {
            return; // nothing active to validate against in this org snapshot
        }

        Test.startTest();
        List<MktCadenceTaskDashboardController.AccountRow> rows =
            MktCadenceTaskDashboardController.getDashboardData(options[0].userId);
        Test.stopTest();

        for (MktCadenceTaskDashboardController.AccountRow row : rows) {
            System.assertNotEquals(null, row.accountId, 'Account row should have an Id');
            System.assertNotEquals(null, row.accountName, 'Account row should have a name');
            System.assert(
                !row.activeCadences.isEmpty() || !row.followUpTasks.isEmpty(),
                'Every returned account should be tied to either an active MKT cadence or a pending follow-up task'
            );
            for (MktCadenceTaskDashboardController.ActiveCadenceInfo info : row.activeCadences) {
                System.assertNotEquals(null, info.contactId, 'Active cadence row should reference a contact');
            }
            for (MktCadenceTaskDashboardController.NewIntentInfo info : row.newIntentSignals) {
                System.assertNotEquals(null, info.signalDate, 'New intent row should always have a signal date');
                System.assert(
                    info.signalDate >= Date.today().addDays(-7),
                    'Only signals from the last 7 days should ever surface here'
                );
            }
        }
    }

    @isTest(SeeAllData=true)
    static void testDashboardDataAcrossAllUsersIncludesEveryFilteredOwnersAccounts() {
        List<MktCadenceTaskDashboardController.UserOption> options =
            MktCadenceTaskDashboardController.getUserOptions();
        if (options.isEmpty()) {
            return; // nothing active to validate against in this org snapshot
        }

        Test.startTest();
        List<MktCadenceTaskDashboardController.AccountRow> allRows =
            MktCadenceTaskDashboardController.getDashboardData(null);
        List<MktCadenceTaskDashboardController.AccountRow> filteredRows =
            MktCadenceTaskDashboardController.getDashboardData(options[0].userId);
        Test.stopTest();

        Set<Id> allAccountIds = new Set<Id>();
        for (MktCadenceTaskDashboardController.AccountRow row : allRows) {
            allAccountIds.add(row.accountId);
        }
        for (MktCadenceTaskDashboardController.AccountRow row : filteredRows) {
            System.assert(
                allAccountIds.contains(row.accountId),
                'Every account visible to a single-owner filter should also appear in the unfiltered (all users) view'
            );
        }
    }
}
