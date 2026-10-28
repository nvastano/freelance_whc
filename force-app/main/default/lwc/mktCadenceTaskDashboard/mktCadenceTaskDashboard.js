import { LightningElement, wire } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import getUserOptions from '@salesforce/apex/MktCadenceTaskDashboardController.getUserOptions';
import getDashboardData from '@salesforce/apex/MktCadenceTaskDashboardController.getDashboardData';

const ALL_USERS_VALUE = '';

export default class MktCadenceTaskDashboard extends LightningElement {
    currentUserId = USER_ID;
    userOptionsList = [];
    selectedOwnerId = ALL_USERS_VALUE;
    searchTerm = '';
    isLoadingOptions = true;
    isLoadingData = true;
    error;
    accountRows = [];
    _defaultApplied = false;

    @wire(getUserOptions)
    wiredUserOptions({ data, error }) {
        this.isLoadingOptions = false;
        if (data) {
            this.userOptionsList = data.map((o) => ({ label: o.name, value: o.userId }));
            if (!this._defaultApplied) {
                this._defaultApplied = true;
                const mine = data.find((o) => o.userId === this.currentUserId);
                if (mine) {
                    this.selectedOwnerId = mine.userId;
                }
            }
        } else if (error) {
            this.error = this.extractErrorMessage(error);
        }
    }

    @wire(getDashboardData, { ownerId: '$ownerIdParam' })
    wiredDashboardData({ data, error }) {
        this.isLoadingData = false;
        if (data) {
            this.accountRows = data;
            this.error = undefined;
        } else if (error) {
            this.error = this.extractErrorMessage(error);
            this.accountRows = [];
        }
    }

    get ownerIdParam() {
        return this.selectedOwnerId || null;
    }

    get userFilterOptions() {
        return [{ label: 'All Users', value: ALL_USERS_VALUE }, ...this.userOptionsList];
    }

    get isLoading() {
        return this.isLoadingOptions || this.isLoadingData;
    }

    handleOwnerChange(event) {
        this.selectedOwnerId = event.detail.value;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    get matchingRows() {
        const term = this.searchTerm.toLowerCase().trim();
        return !term
            ? this.accountRows
            : this.accountRows.filter((r) => r.accountName.toLowerCase().includes(term));
    }

    get filteredRows() {
        return this.matchingRows.map((r) => this.decorateRow(r));
    }

    get newIntentPanelRows() {
        const flattened = [];
        this.matchingRows.forEach((row) => {
            row.newIntentSignals.forEach((s, idx) => {
                flattened.push({
                    key: `${row.accountId}-ni-${idx}`,
                    accountUrl: `/lightning/r/Account/${row.accountId}/view`,
                    accountName: row.accountName,
                    text: `${s.topic} (score ${s.surgeScore}, ${s.signalDate})${
                        s.suggestedCadenceName ? ' → ' + s.suggestedCadenceName : ''
                    }`
                });
            });
        });
        return flattened;
    }

    get hasNewIntentPanelRows() {
        return this.newIntentPanelRows.length > 0;
    }

    decorateRow(row) {
        return {
            accountId: row.accountId,
            accountName: row.accountName,
            accountUrl: `/lightning/r/Account/${row.accountId}/view`,
            activeCadenceLines: row.activeCadences.map((c, idx) => ({
                key: `${row.accountId}-ac-${idx}`,
                text: `${c.cadenceName} — ${c.contactName}`
            })),
            followUpLines: row.followUpTasks.map((t, idx) => ({
                key: `${row.accountId}-fu-${idx}`,
                text: `${t.subject} — ${t.contactName}${t.dueDate ? ' (due ' + t.dueDate + ')' : ''}`
            }))
        };
    }

    get hasRows() {
        return this.filteredRows.length > 0;
    }

    get isEmptyState() {
        return !this.isLoading && !this.error && !this.hasRows;
    }

    get rowCountLabel() {
        return String(this.filteredRows.length);
    }

    get newIntentCount() {
        return this.accountRows.filter((r) => r.newIntentSignals.length > 0).length;
    }

    get pendingFollowUpCount() {
        return this.accountRows.reduce((sum, r) => sum + r.followUpTasks.length, 0);
    }

    extractErrorMessage(error) {
        return (error && error.body && error.body.message) || 'An unknown error occurred.';
    }
}
