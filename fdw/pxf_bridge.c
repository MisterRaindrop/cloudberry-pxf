/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
 */

#include "pxf_bridge.h"
#include "pxf_header.h"

#include "cdb/cdbtm.h"
#include "cdb/cdbvars.h"
#include "utils/builtins.h"

/* helper function declarations */
static void BuildUriForRead(PxfFdwScanState *pxfsstate);
static void BuildUriForWrite(PxfFdwModifyState *pxfmstate);
static size_t FillBuffer(PxfFdwScanState *pxfsstate, char *start, int minlen, int maxlen);

/*
 * Clean up churl related data structures from the PXF FDW modify state.
 */
void
PxfBridgeCleanup(PxfFdwModifyState *pxfmstate)
{
	if (pxfmstate == NULL)
		return;

	churl_cleanup(pxfmstate->churl_handle, false);
	pxfmstate->churl_handle = NULL;

	churl_headers_cleanup(pxfmstate->churl_headers);
	pxfmstate->churl_headers = NULL;

	if (pxfmstate->uri.data)
	{
		pfree(pxfmstate->uri.data);
	}

	if (pxfmstate->options)
	{
		pfree(pxfmstate->options);
	}
}

/*
 * Sets up data before starting import
 */
void
PxfBridgeImportStart(PxfFdwScanState *pxfsstate)
{
	pxfsstate->churl_headers = churl_headers_init();

	BuildUriForRead(pxfsstate);
	BuildHttpHeaders(pxfsstate->churl_headers,
					 pxfsstate->options,
					 pxfsstate->relation,
					 pxfsstate->filter_str,
					 pxfsstate->retrieved_attrs,
					 pxfsstate->projectionInfo);

	pxfsstate->churl_handle = churl_init_download(pxfsstate->uri.data, pxfsstate->churl_headers);

	/* read some bytes to make sure the connection is established */
	churl_read_check_connectivity(pxfsstate->churl_handle);
}

/*
 * Sets up data before starting export
 */
void
PxfBridgeExportStart(PxfFdwModifyState *pxfmstate)
{
	BuildUriForWrite(pxfmstate);
	pxfmstate->churl_headers = churl_headers_init();
	BuildHttpHeaders(pxfmstate->churl_headers,
					 pxfmstate->options,
					 pxfmstate->relation,
					 NULL,
					 NULL,
					 NULL);
	pxfmstate->churl_handle = churl_init_upload(pxfmstate->uri.data, pxfmstate->churl_headers);
}

/*
 * Reads data from the PXF server into the given buffer of a given size
 */
int
PxfBridgeRead(void *outbuf, int minlen, int maxlen, void *extra)
{
	size_t		n = 0;
	PxfFdwScanState *pxfsstate = (PxfFdwScanState *) extra;

	n = FillBuffer(pxfsstate, outbuf, minlen, maxlen);

	if (n == 0)
	{
		/* check if the connection terminated with an error */
		churl_read_check_connectivity(pxfsstate->churl_handle);
	}

	elog(DEBUG5, "pxf PxfBridgeRead: segment %d read %zu bytes from %s",
		 PXF_SEGMENT_ID, n, pxfsstate->options->resource);

	return (int) n;
}

/*
 * Writes data from the given buffer of a given size to the PXF server
 */
int
PxfBridgeWrite(PxfFdwModifyState *pxfmstate, char *databuf, int datalen)
{
	size_t		n = 0;

	if (datalen > 0)
	{
		n = churl_write(pxfmstate->churl_handle, databuf, datalen);
		elog(DEBUG5, "pxf PxfBridgeWrite: segment %d wrote %zu bytes to %s", PXF_SEGMENT_ID, n, pxfmstate->options->resource);
	}

	return (int) n;
}

/*
 * Format the URI for reading by adding PXF service endpoint details
 */
static void
BuildUriForRead(PxfFdwScanState *pxfsstate)
{
	PxfOptions *options = pxfsstate->options;

	resetStringInfo(&pxfsstate->uri);
	appendStringInfo(&pxfsstate->uri, "http://%s:%d/%s/read", options->pxf_host, options->pxf_port, PXF_SERVICE_PREFIX);
	elog(DEBUG2, "pxf_fdw: uri %s for read", pxfsstate->uri.data);
}

/*
 * Format the URI for writing by adding PXF service endpoint details
 */
static void
BuildUriForWrite(PxfFdwModifyState *pxfmstate)
{
	PxfOptions *options = pxfmstate->options;

	resetStringInfo(&pxfmstate->uri);
	appendStringInfo(&pxfmstate->uri, "http://%s:%d/%s/write", options->pxf_host, options->pxf_port, PXF_SERVICE_PREFIX);
	elog(DEBUG2, "pxf_fdw: uri %s with file name for write: %s", pxfmstate->uri.data, options->resource);
}

/*
 * Read data from churl until the buffer is full or there is no more data to be read
 */
static size_t
FillBuffer(PxfFdwScanState *pxfsstate, char *start, int minlen, int maxlen)
{
	size_t		n = 0;
	char	   *ptr = start;
	char	   *minend = ptr + minlen;
	char	   *maxend = ptr + maxlen;

	while (ptr < minend)
	{
		n = churl_read(pxfsstate->churl_handle, ptr, maxend - ptr);
		if (n == 0)
			break;

		ptr += n;
	}

	return ptr - start;
}

/*
 * ============================================================================
 * Parallel Execution Support
 * ============================================================================
 */

/*
 * Build URI for fetching fragment list from PXF server
 */
static void
BuildUriForFragments(PxfFdwScanState *pxfsstate)
{
	PxfOptions *options = pxfsstate->options;

	resetStringInfo(&pxfsstate->uri);
	appendStringInfo(&pxfsstate->uri, "http://%s:%d/%s/fragments",
					 options->pxf_host, options->pxf_port, PXF_SERVICE_PREFIX);
	elog(DEBUG2, "pxf_fdw: uri %s for fragments", pxfsstate->uri.data);
}

/*
 * PxfBridgeFetchFragments
 *		Fetch the list of fragments from PXF server.
 *
 * This function is called by the leader process to get the complete list
 * of fragments that need to be processed. The fragments are stored in
 * pxfsstate->fragments array.
 *
 * Returns the number of fragments fetched.
 *
 * Note: Currently this is a placeholder implementation. The actual
 * implementation will need to:
 * 1. Call the PXF /fragments endpoint
 * 2. Parse the JSON response
 * 3. Store fragment metadata in pxfsstate->fragments
 */
int
PxfBridgeFetchFragments(PxfFdwScanState *pxfsstate)
{
	CHURL_HEADERS headers;
	CHURL_HANDLE handle;
	StringInfoData response;
	char		buffer[8192];
	size_t		bytes_read;
	int			num_fragments = 0;

	elog(DEBUG3, "pxf_fdw: PxfBridgeFetchFragments starting");

	/* Initialize headers */
	headers = churl_headers_init();

	/* Build URI for fragments endpoint */
	BuildUriForFragments(pxfsstate);

	/* Build HTTP headers */
	BuildHttpHeaders(headers,
					 pxfsstate->options,
					 pxfsstate->relation,
					 pxfsstate->filter_str,
					 pxfsstate->retrieved_attrs,
					 pxfsstate->projectionInfo);

	/* Add header to request JSON response */
	churl_headers_append(headers, "Accept", "application/json");

	/* Initialize download */
	handle = churl_init_download(pxfsstate->uri.data, headers);

	/* Read the response */
	initStringInfo(&response);
	while ((bytes_read = churl_read(handle, buffer, sizeof(buffer) - 1)) > 0)
	{
		buffer[bytes_read] = '\0';
		appendStringInfoString(&response, buffer);
	}

	churl_read_check_connectivity(handle);

	elog(DEBUG3, "pxf_fdw: fragments response length=%d", response.len);

	/*
	 * TODO: Parse JSON response to extract fragment metadata.
	 * For now, we use a simplified approach where the server returns
	 * the number of fragments as a simple count.
	 *
	 * Expected JSON format:
	 * {
	 *   "PXFFragments": [
	 *     {"index": 0, "sourceName": "...", "metadata": "..."},
	 *     {"index": 1, "sourceName": "...", "metadata": "..."},
	 *     ...
	 *   ]
	 * }
	 *
	 * For the initial implementation, we'll estimate based on response.
	 * A proper implementation would use a JSON parser.
	 */
	if (response.len > 0)
	{
		/* Simple heuristic: count occurrences of "index" */
		char *ptr = response.data;
		while ((ptr = strstr(ptr, "\"index\"")) != NULL)
		{
			num_fragments++;
			ptr++;
		}

		/* Allocate fragment array if we found any */
		if (num_fragments > 0)
		{
			pxfsstate->fragments = (PxfFragmentData *)
				palloc0(sizeof(PxfFragmentData) * num_fragments);
			pxfsstate->num_fragments = num_fragments;

			/* TODO: Actually parse and populate fragment data */
			elog(DEBUG3, "pxf_fdw: found %d fragments", num_fragments);
		}
	}

	/* Cleanup */
	churl_cleanup(handle, false);
	churl_headers_cleanup(headers);
	pfree(response.data);

	return num_fragments;
}

/*
 * PxfBridgeGetNextFragment
 *		Get the next fragment index for this worker to process.
 *
 * This function atomically increments the next_fragment counter in the
 * shared parallel state and returns the fragment index for this worker
 * to process.
 *
 * Returns -1 if all fragments have been assigned.
 */
int
PxfBridgeGetNextFragment(PxfParallelScanState *pstate)
{
	int			logical_idx;

	if (pstate == NULL)
		return -1;

	SpinLockAcquire(&pstate->mutex);

	if (pstate->next_fragment >= pstate->total_fragments)
	{
		SpinLockRelease(&pstate->mutex);
		return -1;
	}
	logical_idx = pstate->next_fragment++;

	SpinLockRelease(&pstate->mutex);

	/* Map logical → actual: the K-th fragment for segment S is at
	 * actual_index = S + K * seg_count  (round-robin assignment) */
	{
		int			seg_id = PXF_SEGMENT_ID;
		int			seg_count = PXF_SEGMENT_COUNT;
		int			actual_idx = seg_id + logical_idx * seg_count;

		elog(DEBUG3, "pxf_fdw: segment %d: GetNextFragment logical=%d actual=%d",
			 seg_id, logical_idx, actual_idx);

		return actual_idx;
	}
}

/*
 * PxfBridgeImportStartFragment
 *		Start import for a specific fragment in parallel mode.
 *
 * This is similar to PxfBridgeImportStart but includes the fragment
 * index in the request headers so the PXF server knows which specific
 * fragment to return data for.
 */
void
PxfBridgeImportStartFragment(PxfFdwScanState *pxfsstate, int fragmentIndex)
{
	char		fragment_idx_str[16];

	elog(DEBUG3, "pxf_fdw: PxfBridgeImportStartFragment starting for fragment %d",
		 fragmentIndex);

	pxfsstate->churl_headers = churl_headers_init();

	BuildUriForRead(pxfsstate);
	BuildHttpHeaders(pxfsstate->churl_headers,
					 pxfsstate->options,
					 pxfsstate->relation,
					 pxfsstate->filter_str,
					 pxfsstate->retrieved_attrs,
					 pxfsstate->projectionInfo);

	/* Add fragment index header for parallel mode */
	pg_ltoa(fragmentIndex, fragment_idx_str);
	churl_headers_append(pxfsstate->churl_headers, "X-GP-FRAGMENT-INDEX", fragment_idx_str);

	pxfsstate->churl_handle = churl_init_download(pxfsstate->uri.data, pxfsstate->churl_headers);

	/* read some bytes to make sure the connection is established */
	churl_read_check_connectivity(pxfsstate->churl_handle);

	/* Update current fragment tracking */
	pxfsstate->current_fragment = fragmentIndex;
}
