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

#ifndef _PXFBRIDGE_H
#define _PXFBRIDGE_H

#include "libchurl.h"

#include "pxf_option.h"

#include "commands/copy.h"
#include "cdb/cdbvars.h"
#include "nodes/execnodes.h"
#include "nodes/parsenodes.h"
#include "nodes/pg_list.h"
#include "storage/spin.h"

#define PXF_SEGMENT_ID                 GpIdentity.segindex
#define PXF_SEGMENT_COUNT              getgpsegmentCount()

/*
 * Fragment metadata for parallel execution.
 * Stored in local memory, not in shared memory.
 */
typedef struct PxfFragmentData
{
	char	   *source_name;		/* fragment source name (e.g. file path) */
	int			index;				/* fragment index */
	char	   *metadata;			/* fragment metadata (base64 encoded) */
	char	   *profile;			/* optional profile override */
} PxfFragmentData;

/*
 * Shared state for parallel foreign scan.
 * This structure is stored in DSM (dynamic shared memory).
 */
typedef struct PxfParallelScanState
{
	slock_t		mutex;				/* mutex for accessing shared state */
	int			total_fragments;	/* total number of fragments */
	int			next_fragment;		/* next fragment index to be assigned */
	bool		finished;			/* true if all fragments have been processed */
} PxfParallelScanState;

/*
 * Execution state of a foreign scan using pxf_fdw.
 */
typedef struct PxfFdwScanState
{
	CHURL_HEADERS churl_headers;
	CHURL_HANDLE churl_handle;
	StringInfoData uri;
	Relation	relation;
	char	   *filter_str;
	ExprState  *quals;
	List	   *retrieved_attrs;
	PxfOptions *options;
	CopyFromState	cstate;
	ProjectionInfo *projectionInfo;

	/* Parallel execution state */
	bool		is_parallel;		/* true if running in parallel mode */
	PxfParallelScanState *pstate;	/* pointer to shared state in DSM */
	PxfFragmentData *fragments;		/* array of fragment metadata */
	int			num_fragments;		/* total number of fragments */
	int			current_fragment;	/* current fragment being processed */
} PxfFdwScanState;

/*
 * Execution state of a foreign insert operation.
 */
typedef struct PxfFdwModifyState
{
	CopyToState	cstate;			/* state of writing to PXF */

	CHURL_HANDLE churl_handle;	/* curl handle */
	CHURL_HEADERS churl_headers;	/* curl headers */
	StringInfoData uri;			/* rest endpoint URI for modify */
	Relation	relation;
	PxfOptions *options;		/* FDW options */
} PxfFdwModifyState;

/* Clean up churl related data structures from the context */
void		PxfBridgeCleanup(PxfFdwModifyState *context);

/* Sets up data before starting import */
void		PxfBridgeImportStart(PxfFdwScanState *pxfsstate);

/* Sets up data before starting export */
void		PxfBridgeExportStart(PxfFdwModifyState *pxfmstate);

/* Reads data from the PXF server into the given buffer of a given size */
int			PxfBridgeRead(void *outbuf, int minlen, int maxlen, void *extra);

/* Writes data from the given buffer of a given size to the PXF server */
int			PxfBridgeWrite(PxfFdwModifyState *context, char *databuf, int datalen);

/* Parallel execution support */

/* Fetch fragment list from PXF server */
int			PxfBridgeFetchFragments(PxfFdwScanState *pxfsstate);

/* Get the next fragment index for this worker (thread-safe) */
int			PxfBridgeGetNextFragment(PxfParallelScanState *pstate);

/* Start import for a specific fragment in parallel mode */
void		PxfBridgeImportStartFragment(PxfFdwScanState *pxfsstate, int fragmentIndex);

#endif							/* _PXFBRIDGE_H */
