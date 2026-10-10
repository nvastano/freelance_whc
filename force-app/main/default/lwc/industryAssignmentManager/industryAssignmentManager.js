import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getAssignments from '@salesforce/apex/IndustryAssignmentController.getAssignments';
import getLTMembers from '@salesforce/apex/IndustryAssignmentController.getLTMembers';
import getAssignmentGroups from '@salesforce/apex/IndustryAssignmentController.getAssignmentGroups';
import getPrimaryIndustryValues from '@salesforce/apex/IndustryAssignmentController.getPrimaryIndustryValues';
import getSubIndustryValues from '@salesforce/apex/IndustryAssignmentController.getSubIndustryValues';
import getUsedSubIndustries from '@salesforce/apex/IndustryAssignmentController.getUsedSubIndustries';
import saveAssignment from '@salesforce/apex/IndustryAssignmentController.saveAssignment';
import deleteAssignment from '@salesforce/apex/IndustryAssignmentController.deleteAssignment';
import bulkSaveAssignments from '@salesforce/apex/IndustryAssignmentController.bulkSaveAssignments';

const EMPTY_RECORD = {
    Id: null,
    ZI_Primary_Industry__c: '',
    ZI_Sub_Industry__c: '',
    Assignment_Group__c: '',
    LT_Member__c: '',
    Active__c: true
};

export default class IndustryAssignmentManager extends LightningElement {
    @track searchTerm = '';
    @track filterPrimaryIndustry = '';
    @track filterGroup = '';
    @track filterLTMember = '';
    @track activeOnly = false;
    @track showNewRow = false;
    @track newRecord = { ...EMPTY_RECORD };

    // Bulk edit state
    @track selectedIds = new Set();
    @track bulkLTMember = '';
    @track bulkGroup = '';
    @track bulkActive = '';

    // Pagination
    @track currentPage = 1;
    @track pageSize = 25;

    pageSizeOptions = [
        { value: '25',  label: '25 per page' },
        { value: '50',  label: '50 per page' },
        { value: '100', label: '100 per page' }
    ];

    _wiredAssignments;
    _wiredUsed;
    @track allRecords = [];
    @track primaryIndustryOptions = [];
    @track subIndustryOptions = [];
    @track ltMemberOptions = [];
    @track usedSubIndustries = new Set();
    @track groupEditOptions = []; // ID-based, used in row edit dropdowns

    // Name-based options for the filter toolbar
    groupOptions = [
        { value: '', label: '—' },
        { value: 'Pod 1', label: 'Pod 1' },
        { value: 'Pod 2', label: 'Pod 2' }
    ];

    bulkGroupOptions = [
        { value: 'Pod 1', label: 'Pod 1' },
        { value: 'Pod 2', label: 'Pod 2' }
    ];

    bulkActiveOptions = [
        { value: 'true',  label: 'Active' },
        { value: 'false', label: 'Inactive' }
    ];

    // ── Wire calls ──────────────────────────────────────────────────────────
    @wire(getAssignments)
    wiredAssignments(result) {
        this._wiredAssignments = result;
        if (result.data) {
            this.allRecords = result.data.map(r => ({ ...r, _selected: false }));
            this.selectedIds = new Set();
        }
    }

    @wire(getUsedSubIndustries)
    wiredUsed(result) {
        this._wiredUsed = result;
        if (result.data) {
            this.usedSubIndustries = new Set(result.data);
        }
    }

    @wire(getAssignmentGroups)
    wiredGroups({ data }) {
        if (data) {
            this.groupEditOptions = data.map(d => ({ value: d.value, label: d.label }));
            // Also rebuild bulk options from real IDs
            this.bulkGroupOptions = data.map(d => ({ value: d.value, label: d.label }));
        }
    }

    @wire(getPrimaryIndustryValues)
    wiredPrimary({ data }) {
        if (data) {
            this.primaryIndustryOptions = [
                { value: '', label: 'All Industries' },
                ...data.map(d => ({ value: d.value, label: d.label }))
            ];
        }
    }

    @wire(getSubIndustryValues)
    wiredSub({ data }) {
        if (data) {
            this.subIndustryOptions = data.map(d => ({ value: d.value, label: d.label }));
        }
    }

    @wire(getLTMembers)
    wiredMembers({ data }) {
        if (data) {
            this.ltMemberOptions = [
                { value: '', label: 'All Members' },
                ...data.map(d => ({ value: d.value, label: d.label }))
            ];
            this.bulkLTMemberOptions = data.map(d => ({ value: d.value, label: d.label }));
        }
    }

    // ── Computed ─────────────────────────────────────────────────────────────
    get filteredRecords() {
        const search = this.searchTerm.toLowerCase();
        return this.allRecords.filter(r => {
            if (search && !(r.ZI_Sub_Industry__c || '').toLowerCase().includes(search)) return false;
            if (this.filterPrimaryIndustry && r.ZI_Primary_Industry__c !== this.filterPrimaryIndustry) return false;
            if (this.filterGroup && r.Assignment_Group__r?.Name !== this.filterGroup) return false;
            if (this.filterLTMember && r.LT_Member__c !== this.filterLTMember) return false;
            if (this.activeOnly && !r.Active__c) return false;
            return true;
        });
    }

    get filteredCount()  { return this.filteredRecords.length; }
    get totalCount()     { return this.allRecords.length; }
    get selectedCount()  { return this.selectedIds.size; }
    get hasSelection()   { return this.selectedIds.size > 0; }
    get isBulkApplyDisabled() {
        return !this.bulkLTMember && !this.bulkGroup && this.bulkActive === '';
    }
    get allSelected() {
        const page = this.paginatedRecords;
        return page.length > 0 && page.every(r => this.selectedIds.has(r.Id));
    }

    // Pagination
    get totalPages()        { return Math.max(1, Math.ceil(this.filteredRecords.length / this.pageSize)); }
    get hasPrevious()       { return this.currentPage > 1; }
    get hasNext()           { return this.currentPage < this.totalPages; }
    get noPrevious()        { return !this.hasPrevious; }
    get noNext()            { return !this.hasNext; }
    get pageStart()         { return this.filteredRecords.length === 0 ? 0 : (this.currentPage - 1) * this.pageSize + 1; }
    get pageEnd()           { return Math.min(this.currentPage * this.pageSize, this.filteredRecords.length); }
    get pageLabel()         { return `${this.pageStart}–${this.pageEnd} of ${this.filteredRecords.length}`; }
    get pageSizeStr()       { return String(this.pageSize); }

    get paginatedRecords() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.filteredRecords.slice(start, start + this.pageSize);
    }

    get filteredSubOptions() {
        if (!this.filterPrimaryIndustry) return this.subIndustryOptions;
        const validSubs = new Set(
            this.allRecords
                .filter(r => r.ZI_Primary_Industry__c === this.filterPrimaryIndustry)
                .map(r => r.ZI_Sub_Industry__c)
        );
        return this.subIndustryOptions.filter(o => validSubs.has(o.value));
    }

    // Sub-industry options with already-used values removed (for new record form)
    get availableSubIndustryOptions() {
        return this.subIndustryOptions.filter(o => !this.usedSubIndustries.has(o.value));
    }

    // Returns used sub-industries as a plain array for passing to child components
    get usedSubIndustriesArray() {
        return [...this.usedSubIndustries];
    }

    // ── Filter handlers ──────────────────────────────────────────────────────
    handleSearch(e)        { this.searchTerm = e.target.value; this.currentPage = 1; }
    handlePrimaryFilter(e) { this.filterPrimaryIndustry = e.detail.value; this.searchTerm = ''; this.currentPage = 1; }
    handleGroupFilter(e)   { this.filterGroup = e.detail.value; this.currentPage = 1; }
    handleLTMemberFilter(e){ this.filterLTMember = e.detail.value; this.currentPage = 1; }
    handleActiveToggle(e)  { this.activeOnly = e.target.checked; this.currentPage = 1; }

    clearFilters() {
        this.searchTerm = '';
        this.filterPrimaryIndustry = '';
        this.filterGroup = '';
        this.filterLTMember = '';
        this.activeOnly = false;
        this.currentPage = 1;
    }

    // ── Pagination handlers ───────────────────────────────────────────────────
    handlePreviousPage() { if (this.hasPrevious) this.currentPage -= 1; }
    handleNextPage()     { if (this.hasNext) this.currentPage += 1; }
    handlePageSizeChange(e) {
        this.pageSize = parseInt(e.detail.value, 10);
        this.currentPage = 1;
    }

    // ── Selection handlers ───────────────────────────────────────────────────
    handleRowSelect(e) {
        const { recordId, selected } = e.detail;
        const newSet = new Set(this.selectedIds);
        selected ? newSet.add(recordId) : newSet.delete(recordId);
        this.selectedIds = newSet;
        // update _selected flag on the record for row re-render
        this.allRecords = this.allRecords.map(r =>
            r.Id === recordId ? { ...r, _selected: selected } : r
        );
    }

    handleSelectAll(e) {
        const checked = e.target.checked;
        const newSet = new Set(this.selectedIds);
        this.paginatedRecords.forEach(r => {
            checked ? newSet.add(r.Id) : newSet.delete(r.Id);
        });
        this.selectedIds = newSet;
        const pageIds = new Set(this.paginatedRecords.map(r => r.Id));
        this.allRecords = this.allRecords.map(r =>
            pageIds.has(r.Id) ? { ...r, _selected: checked } : r
        );
    }

    clearSelection() {
        this.selectedIds = new Set();
        this.allRecords = this.allRecords.map(r => ({ ...r, _selected: false }));
        this.bulkLTMember = '';
        this.bulkGroup = '';
        this.bulkActive = '';
    }

    // ── Bulk edit handlers ───────────────────────────────────────────────────
    handleBulkLTMember(e) { this.bulkLTMember = e.detail.value; }
    handleBulkGroup(e)    { this.bulkGroup = e.detail.value; }
    handleBulkActive(e)   { this.bulkActive = e.detail.value; }

    async handleBulkApply() {
        if (this.isBulkApplyDisabled) return;

        const records = [...this.selectedIds].map(id => {
            const update = { Id: id };
            if (this.bulkLTMember)    update.LT_Member__c        = this.bulkLTMember;
            if (this.bulkGroup)       update.Assignment_Group__c  = this.bulkGroup; // already an ID
            if (this.bulkActive !== '') update.Active__c           = this.bulkActive === 'true';
            return update;
        });

        try {
            await bulkSaveAssignments({ records });
            await refreshApex(this._wiredAssignments);
            this.clearSelection();
            this.dispatchEvent(new ShowToastEvent({
                title: `${records.length} record${records.length > 1 ? 's' : ''} updated`,
                variant: 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err.body?.message || 'Unknown error',
                variant: 'error'
            }));
        }
    }

    // ── New record ───────────────────────────────────────────────────────────
    handleNewClick() {
        this.newRecord = { ...EMPTY_RECORD };
        this.showNewRow = true;
    }

    handleNewCancel() { this.showNewRow = false; }

    async handleNewSave(e) {
        try {
            await saveAssignment({ record: e.detail });
            this.showNewRow = false;
            await Promise.all([refreshApex(this._wiredAssignments), refreshApex(this._wiredUsed)]);
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error saving',
                message: err.body?.message || 'Unknown error',
                variant: 'error'
            }));
        }
    }

    // ── Row events ───────────────────────────────────────────────────────────
    async handleRowSave(e) {
        try {
            await saveAssignment({ record: e.detail });
            await Promise.all([refreshApex(this._wiredAssignments), refreshApex(this._wiredUsed)]);
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error saving',
                message: err.body?.message || 'Unknown error',
                variant: 'error'
            }));
        }
    }

    async handleRowDelete(e) {
        try {
            await deleteAssignment({ recordId: e.detail });
            await Promise.all([refreshApex(this._wiredAssignments), refreshApex(this._wiredUsed)]);
            this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error deleting',
                message: err.body?.message || 'Unknown error',
                variant: 'error'
            }));
        }
    }
}