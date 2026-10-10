import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getSegments from '@salesforce/apex/BusinessSegmentManagerController.getSegments';
import getCycleValues from '@salesforce/apex/BusinessSegmentManagerController.getCycleValues';
import saveSegment from '@salesforce/apex/BusinessSegmentManagerController.saveSegment';
import deleteSegment from '@salesforce/apex/BusinessSegmentManagerController.deleteSegment';

const EMPTY_RECORD = {
    Id: null,
    Business__c: '',
    Cycle__c: ''
};

export default class BusinessSegmentManager extends LightningElement {
    @track searchTerm = '';
    @track filterCycle = '';
    @track showNewRow = false;
    @track newRecord = { ...EMPTY_RECORD };

    @track currentPage = 1;
    @track pageSize = 25;

    pageSizeOptions = [
        { value: '25', label: '25 per page' },
        { value: '50', label: '50 per page' },
        { value: '100', label: '100 per page' }
    ];

    _wiredSegments;
    @track allRecords = [];
    @track cycleOptions = [];

    get cycleFilterOptions() {
        return [{ value: '', label: 'All Cycles' }, ...this.cycleOptions];
    }

    @wire(getSegments)
    wiredSegments(result) {
        this._wiredSegments = result;
        if (result.data) {
            this.allRecords = result.data;
        }
    }

    @wire(getCycleValues)
    wiredCycles({ data }) {
        if (data) {
            this.cycleOptions = data.map((d) => ({ value: d.value, label: d.label }));
        }
    }

    get filteredRecords() {
        const search = this.searchTerm.toLowerCase();
        return this.allRecords.filter((r) => {
            if (search && !(r.Business__c || '').toLowerCase().includes(search)) return false;
            if (this.filterCycle && r.Cycle__c !== this.filterCycle) return false;
            return true;
        });
    }

    get hasFilters() {
        return !!this.searchTerm || !!this.filterCycle;
    }

    get hasRecords() {
        return this.filteredRecords.length > 0;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredRecords.length / this.pageSize));
    }
    get hasPrevious() {
        return this.currentPage > 1;
    }
    get hasNext() {
        return this.currentPage < this.totalPages;
    }
    get noPrevious() {
        return !this.hasPrevious;
    }
    get noNext() {
        return !this.hasNext;
    }
    get pageStart() {
        return this.filteredRecords.length === 0 ? 0 : (this.currentPage - 1) * this.pageSize + 1;
    }
    get pageEnd() {
        return Math.min(this.currentPage * this.pageSize, this.filteredRecords.length);
    }
    get pageLabel() {
        return `${this.pageStart}–${this.pageEnd} of ${this.filteredRecords.length}`;
    }
    get pageSizeStr() {
        return String(this.pageSize);
    }

    get paginatedRecords() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.filteredRecords.slice(start, start + this.pageSize);
    }

    handleSearch(e) {
        this.searchTerm = e.target.value;
        this.currentPage = 1;
    }
    handleCycleFilter(e) {
        this.filterCycle = e.detail.value;
        this.currentPage = 1;
    }
    clearFilters() {
        this.searchTerm = '';
        this.filterCycle = '';
        this.currentPage = 1;
    }

    handlePreviousPage() {
        if (this.hasPrevious) this.currentPage -= 1;
    }
    handleNextPage() {
        if (this.hasNext) this.currentPage += 1;
    }
    handlePageSizeChange(e) {
        this.pageSize = parseInt(e.detail.value, 10);
        this.currentPage = 1;
    }

    handleNewClick() {
        this.newRecord = { ...EMPTY_RECORD };
        this.showNewRow = true;
    }

    handleNewCancel() {
        this.showNewRow = false;
    }

    async handleNewSave(e) {
        try {
            await saveSegment({ record: e.detail });
            this.showNewRow = false;
            await refreshApex(this._wiredSegments);
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error saving',
                    message: (err.body && err.body.message) || 'Unknown error',
                    variant: 'error'
                })
            );
        }
    }

    async handleRowSave(e) {
        try {
            await saveSegment({ record: e.detail });
            await refreshApex(this._wiredSegments);
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error saving',
                    message: (err.body && err.body.message) || 'Unknown error',
                    variant: 'error'
                })
            );
        }
    }

    async handleRowDelete(e) {
        try {
            await deleteSegment({ recordId: e.detail });
            await refreshApex(this._wiredSegments);
            this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error deleting',
                    message: (err.body && err.body.message) || 'Unknown error',
                    variant: 'error'
                })
            );
        }
    }
}
