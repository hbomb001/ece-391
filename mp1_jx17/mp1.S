
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

		IOCTL_BOUND = 3
		LOCATION_BOUND = 1999

		SHORT_TYPE_SIZE = 16


# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX
mp1_poke:
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret

/* void mp1_rtc_tasklet(unsigned long);

 Interface: C-style arguments
    Inputs: every time an RTC interrupt is generated, mp1_rtc_tasklet is called.
   Outputs: every struct in the list gets a decrement on countdown, once the countdown 
			is decremented to zero, the on/off chars get switched. The countdown gets updated 
			to the opposite length
 Registers: %ebx for local variable to hold the list head*/
mp1_rtc_tasklet: 
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx /*callee save %ebx as local variable*/

	movl mp1_list_head, %ebx
	/*ebx holds the current addr*/

tasklet_op_loop:
	/*if head is null,
	  function ends */
	cmpl $0, %ebx
	jz tasklet_return

	/*decrement the countdown
	  if the countdown didn't reach zero jump*/
	decw COUNTDOWN(%ebx)
	cmpw $0, COUNTDOWN(%ebx)
	jnz tasklet_finish_status
	
	/*now countdown is zero,
	  check if the status is 1 or zero, jump to corresponding block*/
	cmpw $1, STATUS(%ebx)
	jz tasklet_status_one
	/*not jumping means a zero*/

	/*OFF STATUS
	  put on_char, update the countdown with on_length*/

	/*clean eax and put location into ax
	  location*2 is the real location
	  put on_char into cl*/
	xorl %eax, %eax
	movw LOCATION(%ebx), %ax
	addw %ax, %ax
	movb ON_CHAR(%ebx), %cl

	/*caller save edx, call poke*/
	pushl %edx
	call mp1_poke
	popl %edx

	/*copy on_length to countdown 
	  using ebx to hold the addr allocated*/
	movw ON_LENGTH(%ebx), %ax
	movw %ax, COUNTDOWN(%ebx)

	/*switch status to 1*/
	movw $1, STATUS(%ebx)

	jmp tasklet_finish_status

tasklet_status_one:
	/*ON STATUS
	  put off_char, update the countdown with off_length, switch status to 0*/

	/*clean eax and put location into ax
	  location*2 is the real location
	  put off_char into cl*/
	xorl %eax, %eax
	movw LOCATION(%ebx), %ax
	addw %ax, %ax
	movb OFF_CHAR(%ebx), %cl

	/*caller save edx, call poke*/
	pushl %edx
	call mp1_poke
	popl %edx

	/*copy off_length to countdown 
	  using ebx to hold the addr allocated*/
	movw OFF_LENGTH(%ebx), %ax
	movw %ax, COUNTDOWN(%ebx)

	/*switch status to 0*/
	movw $0, STATUS(%ebx)

tasklet_finish_status:
	movl NEXT(%ebx), %eax
	movl %eax, %ebx
	jmp tasklet_op_loop

tasklet_return:
	popl %ebx
	leave 
	ret

/* void mp1_rtc_ioctl(unsigned long number);

 Interface: C-style arguments
    Inputs: the number determining the function to go to 
			0 : mp1_ioctl_add
			1 : mp1_ioctl_remove
			2 : mp1_ioctl_find
			3 : mp1_ioctl_sync
   Outputs: the program flow gets navigated to the corresponding function
 Registers: %eax : the number input */
mp1_ioctl:
	
	/*validate %eax
	  if not valid go to exception*/
	movl 8(%esp), %eax /*8 because the %esp and return addr takes 4 bytes each*/
	cmpl $0, %eax
	jl exception
	cmpl $IOCTL_BOUND, %eax
	jg exception
	
	/*argument valid, 
	  go to the corresponding jump_table*/
	jmp *jump_table(,%eax,4)

exception:
	/*return -1*/
	movl $-1, %eax
	ret

jump_table:
.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync

/* void mp1_rtc_add(unsigned long number);

 Interface: C-style arguments
    Inputs: the user-level pointer to a mp1_blink_struct
   Outputs: the list gets inserted a new struct at the head and return 0 if successful 
			return -1 if failed
 Registers: %ebx : the variable to hold newly allocated memory address */
mp1_ioctl_add:
	/*error conditions to be considered:
	  	--malloc return null
		--arg empty 
		--copy from user returns anything other than 0
		--location out of bound
	*/
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx /*callee save %ebx as local variable to hold the newly allocated memory address*/

	pushl $STRUCT_SIZE
	call mp1_malloc
	addl $4, %esp /*tear down structSize, and 4 because of the STRUCT_SIZE takes 4 bytes*/
	movl %eax, %ebx
	/*now %ebx holds the newly allocated*/

	/*if malloc returned null value, 
	  return without freeing*/
	cmpl $0, %eax
	jz add_return

	/*if arg is empty
	  return with freeing*/		
	cmpl $0, 8(%ebp) /*8 because the %esp and return addr takes 4 bytes each*/
	jz add_error

	/*copy from user
	  3 arguments: rtl: n, from, to*/
	pushl $STRUCT_SIZE
	pushl 8(%ebp) /*arg, 8 because the %esp and return addr takes 4 bytes each*/
	pushl %eax /*newly allocated addr*/
	call mp1_copy_from_user
	addl $12, %esp /*12 because of 3 long arguments*/

	/*if copy returns anything other than 0
	  free the previously allocated addr, function ends*/
	cmpl $0, %eax
	jnz add_error
	
	/*if location is out of bound
	  free the previously allocated addr, function ends*/
	cmpw $LOCATION_BOUND, LOCATION(%ebx)
	ja add_error
	
	/*copy on_length to countdown 
	  using ebx to hold the addr allocated*/
	movw ON_LENGTH(%ebx), %ax
	movw %ax, COUNTDOWN(%ebx)

	/*set status to 1
	  using ebx to hold the addr allocated*/
	movw $1, STATUS(%ebx)

	/*set next to original head, mp1_list_head
	  moving mp1_list_head to the new struct
	  using ebx to hold the addr allocated*/
	movl mp1_list_head, %eax
	movl %eax, NEXT(%ebx)
	movl %ebx, mp1_list_head


	/*prepare for poke
	  2 registers, on_char->cl and location->ax*/

	/*clean eax and put location into ax
	  location*2 is the real location*/
	xorl %eax, %eax
	movw LOCATION(%ebx), %ax
	addw %ax, %ax
	movb ON_CHAR(%ebx), %cl

	/*caller save edx, call poke*/
	pushl %edx
	call mp1_poke
	popl %edx

	/*successful return
	  pop ebx, return 0 */
	popl %ebx
	movl $0, %eax
	leave
	ret

add_error:
	/*use the returned addr to free before function ends
	  use %ebx to contain the addr to be freed */
	pushl %ebx
	call mp1_free
	addl $4, %esp /*4 because the %ebx takes 4 bytes*/

add_return:
	/*return, function ends
	  pop callee saved variable %ebx, return -1*/
	popl %ebx
	movl $-1, %eax
	leave
	ret
/* void mp1_rtc_remove(unsigned long number);

 Interface: C-style arguments
    Inputs: the location of the struct to be removed
   Outputs: the list gets removed of the desired struct and return 0 if successful 
			return -1 if failed
 Registers: %ebx : the pointer to the current struct in process
            %esi : the pointer to the parent struct of the to-be-removed
			%edi : the pointer to the next struct of the to-be-removed */
mp1_ioctl_remove:
	/*error conditions to be considered:
		**arg empty: this should not be considered because 0 input means remove 
					the struct at location 0
		--list empty
		--location out of bound
		--didn't find
	*/
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx 
	pushl %esi 
	pushl %edi 


	/*process the inputs, 
	  extract the locations into corresponding registers,
	  clean the upper 16 bits of %edi to hold the location*/
	movl mp1_list_head, %ebx   
	xorl %edi, %edi
	movw 8(%ebp), %di /*8 because the %esp and return addr takes 4 bytes each*/
	/* now %di holds the location*/

	/*if location is out of bound
	  function ends*/
	cmpw $LOCATION_BOUND, %di
	ja remove_error_return

	/*if list is empty,
	  function ends*/
	cmpl $0, %ebx
	jz remove_error_return

	/*check if the location is at the head of the list
	  if it is, skip search list */
	cmpw LOCATION(%ebx), %di
	jnz remove_location_not_head

	/*not jumping means the location is at the head of the list*/
	movl NEXT(%ebx), %esi
	/*now %esi has the pointer to the child struct of the to-be-removed struct 
	  %ebx has the pointer to the to-be-removed struct*/
		
	/*remove the struct from the list;
	  set the list head pointer to the pointer to the child struct(%esi)
	  free the to-be-removed (%ebx) struct*/
	movl %esi, mp1_list_head
	pushl %ebx
	call mp1_free
	addl $4, %esp /*4 because %ebx takes 4 bytes on the stack*/	

	/*successful return */
	popl %edi
	popl %esi
	popl %ebx
	movl $0, %eax
	leave
	ret	

remove_location_not_head:
	/*use search_list to find first location's parent
	  2 parameters: rtl: list, location
	  get real pointer of the desired struct*/

	pushl mp1_list_head 
	pushw %di
	call search_list
	addl $6, %esp /*6 because the parameters are 1 long and 1 short*/
	
	/*if search_list returns -1
	  functions ends, return -1*/
	cmpl $-1, %eax
	jz remove_error_return
	
	movl NEXT(%eax), %esi
	movl NEXT(%esi), %esi
	movl NEXT(%eax), %edi
	/*now %eax has the parent pointer to the parent struct of the to-be-removed struct 
	  %esi has the pointer to the child struct of the to-be-removed struct 
	  %edi has the pointer to the to-be-removed struct*/

	/*remove the struct from the list;
	  set the parent struct's (%eax's) NEXT to the child struct (%esi),
	  free the to-be-removed (%edi) struct*/
	
	movl %esi, NEXT(%eax)
	pushl %edi
	call mp1_free
	addl $4, %esp /*4 because %edi takes 4 bytes on the stack*/
	
	/*successful return */
	popl %edi
	popl %esi
	popl %ebx
	movl $0, %eax
	leave
	ret	

remove_error_return:
	popl %edi
	popl %esi
	popl %ebx
	movl $-1, %eax
	leave
	ret	

/* void mp1_rtc_find(unsigned long number);

 Interface: C-style arguments
    Inputs: a user level pointer to a struct with the location of the to-be-found struct
   Outputs: the user leverl struct gets copied from the list of the found struct and return 0 if successful 
			return -1 if failed
 Registers: %ebx : the pointer to the allocated memory
            %esi : the pointer to the existing list
			%edi (%di) : the variable holding the location */
mp1_ioctl_find:
	/*error conditions to be considered:
	  	--malloc return null
		--arg empty 
		--copy from user returns anything other than 0
		--location out of bound
		--copy to user returns anything other than 0
		--didn't find
		--empty list
	*/
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx /*callee save %ebx as the pointer to the allocated memory*/
	pushl %esi /*callee save %esi as the pointer to the existing list*/
	pushl %edi /*callee save %edi (%di) as the variable holding the location*/

	pushl $STRUCT_SIZE
	call mp1_malloc
	addl $4, %esp /*4 because STRUCT_SIZE is an unsigned long*/
	movl %eax, %ebx
	/*now %ebx holds the newly allocated addr*/

	/*if malloc returned null value,
	  return without freeing*/
	cmpl $0, %eax
	jz find_return

	/*if arg is empty
	  return with freeing*/	
	cmpl $0, 8(%ebp) /*arg, 8 because %ebp takes 4 bytes, return address takes 4 bytes*/
	jz find_error

	/*copy from user
	  3 arguments: rtl: n, from, to*/
	pushl $STRUCT_SIZE
	pushl 8(%ebp) /*arg, 8 because %ebp takes 4 bytes, return address takes 4 bytes*/
	pushl %eax /*newly allocated addr*/
	call mp1_copy_from_user
	addl $12, %esp /*12 because of 3 long arguments*/

	/*if copy_from_user returns anything other than 0
	  free the previously allocated addr, function ends*/
	cmpl $0, %eax
	jnz find_error

	/*if location is out of bound
	  free the previously allocated addr, function ends*/
	cmpw $LOCATION_BOUND, LOCATION(%ebx)
	ja find_error

	/*use %di as the variable holding the target location
	  %esi as the pointer to the existing list*/
	movw LOCATION(%ebx), %di
	movl mp1_list_head, %esi

	/*if list is empty, 
	return with freeing*/
	cmpl $0, %esi
	jz find_error

	/*check if the location is at the head*/
	cmpw LOCATION(%esi), %di
	jnz find_not_head

	/*not jumping means the location is at the head
	  put the head pointer in %eax*/
	movl mp1_list_head, %eax
	jmp find_finish_search

find_not_head:
	/*use search_list to find the location's parent pointer
	  2 parameters: rtl: list, location*/
	pushl mp1_list_head
	pushw %di
	call search_list
	addl $6, %esp /*6 because the parameters are 1 long and 1 short*/

	/*if search list returns -1
	  return with freeing*/
	cmpl $-1, %eax
	jz find_error
	/*now %eax holds the parent pointer to the desired location
	  get the real pointer*/
	movl NEXT(%eax), %eax


find_finish_search:

	/*now the location on list found, 
	  copy the element on list to the userlevel struct
	  3 arguments: rtl: n, from, to*/
	pushl $STRUCT_SIZE
	pushl %eax /*element on list*/
	pushl 8(%ebp) /*arg, 8 because %ebp takes 4 bytes, return address takes 4 bytes*/
	call mp1_copy_to_user
	addl $12, %esp /*12 because of 3 long arguments*/

	/*if copy returns anything other than 0
	  free the previously allocated addr, function ends*/
	cmpl $0, %eax
	jnz find_error

	/*successful search 
	  freeing the allocated memory, function ends with return value 0*/
	pushl %ebx
	call mp1_free
	addl $4, %esp /*tear down, 4 because %ebx takes 4 bytes*/
	
	popl %edi
	popl %esi
	popl %ebx
	movl $0, %eax
	leave
	ret

find_error:
	/*use the returned addr to free before function ends
	  use %ebx to contain the addr to be freed */
	pushl %ebx
	call mp1_free
	addl $4, %esp /*tear down, 4 because %ebx takes 4 bytes*/
	
find_return:
	/*return, function ends
	  pop callee saved variable %ebx, return -1*/
	popl %edi
	popl %esi
	popl %ebx
	movl $-1, %eax
	leave
	ret
/* void mp1_rtc_sync(unsigned long number);

 Interface: C-style arguments
    Inputs: an unsigned long number containing 2 short locations, the higher 16 bits being the first location and lower, the second.
   Outputs: the timing information (on_length, off_length, countdown, status) of the struct with the 
   			second locatioin gets synced to the first struct and return 0 if successful 
			return -1 if failed	
 Registers: %ebx : the pointer to the current struct
            %esi (%si) : the variable holding the second location
			%edi (%di) : the variable holding the first location */
mp1_ioctl_sync:
	/*error conditions to be considered:
		--empty list
		--didn't find
	*/
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx 
	pushl %esi 
	pushl %edi 

	/*process the inputs, 
	  extract the locations into corresponding registers*/
	xorl %esi, %esi
	movw 8(%ebp), %si /*arg, 8 because %ebp takes 4 bytes, return address takes 4 bytes*/
	movl 8(%ebp), %edi /*arg, 8 because %ebp takes 4 bytes, return address takes 4 bytes*/
	shrl $SHORT_TYPE_SIZE, %edi /*now %di holds the first location*/
	movl mp1_list_head, %ebx 

	/*if list is empty,
	  return error to avoid segfault*/
	cmpl $0, %ebx
	jz sync_error_return

	/*check if first location is at the head of the list
	  if it is, skip search list */
	cmpw LOCATION(%ebx), %di
	jnz sync_first_location_not_head

	/*first location is head
	  move mp1_list_head into %edi*/
	movl mp1_list_head, %edi
	jmp sync_second_location

sync_first_location_not_head:

	/*use search_list to find first location's parent
	  2 parameters: rtl: list, location
	  get real pointer of the desired struct*/

	pushl mp1_list_head 
	pushw %di
	call search_list
	addl $6, %esp /*6 because the parameters are 1 long and 1 short*/
	
	/*if search_list returns -1
	  functions ends, return -1*/
	cmpl $-1, %eax
	jz sync_error_return

	/*get the real pointer to the second location*/
	movl %eax, %edi
	movl NEXT(%edi), %edi

sync_second_location:
	/*check if second location is at the head of the list
	  if it is, skip search list */
	movl mp1_list_head, %ebx 
	cmpw LOCATION(%ebx), %si
	jnz sync_second_location_not_head

	/*second location is head
	  move mp1_list_head into %esi
	  get real pointer to the desired struct*/
	movl mp1_list_head, %esi

	jmp sync_both_location_finished

sync_second_location_not_head:
	/*use search_list to find first location's parent
	  2 parameters: rtl: list, location*/
	pushl mp1_list_head 
	pushw %si 
	call search_list
	addl $6, %esp /*6 because the parameters are 1 long and 1 short*/
	
	/*if search_list returns -1
	  functions ends, return -1*/
	cmpl $-1, %eax
	jz sync_error_return

	/*get the real pointer to the second location*/
	movl %eax, %esi
	movl NEXT(%esi), %esi

sync_both_location_finished:
	/*copy ON_LENGTH*/
	movw ON_LENGTH(%edi), %ax
	movw %ax, ON_LENGTH(%esi)

	/*copy OFF_LENGTH*/
	movw OFF_LENGTH(%edi), %ax
	movw %ax, OFF_LENGTH(%esi)

	/*copy COUNTDOWN*/
	movw COUNTDOWN(%edi), %ax
	movw %ax, COUNTDOWN(%esi)

	/*copy STATUS*/
	movw STATUS(%edi), %ax
	movw %ax, STATUS(%esi)

	/*clean eax and put location into ax
	  location*2 is the real location*/
	xorl %eax, %eax
	movw LOCATION(%esi), %ax
	addw %ax, %ax

	/*choose right char by status*/
	cmpw $0, STATUS(%edi)
	jz sync_off_status

	/*on status*/
	movb ON_CHAR(%edi), %cl
	jmp	sync_char_chosen

sync_off_status:
	/*off status*/
	movb OFF_CHAR(%esi), %cl

sync_char_chosen:
	/*caller save edx, call poke*/
	pushl %edx
	call mp1_poke
	popl %edx	

	/*successful return */
	popl %edi
	popl %esi
	popl %ebx
	movl $0, %eax
	leave
	ret

sync_error_return:
	/*if there is an error, 
	  return -1*/
	popl %edi
	popl %esi
	popl %ebx
	movl $-1, %eax
	leave
	ret

/*mp1_blink_struct* search_list(usigned short location, mp1_blink_struct* list );
 Interface: C-style arguments 
    Inputs: list - the pointer pointing to the list to be searched on 
           location - the location of the struct we are finding 
   Outputs: the pointer to the parent struct of the desired struct in %eax
		   if there is no parent struct of desired location or an error occurs, return -1
 Registers: ebx: pointer to the location
		   esi: pointer to the current struct
		   edi: pointer to the parent struct */
search_list:
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx 
	pushl %esi 
	pushl %edi 

	/* initialize the registers with the input parameters*/
	movw 8(%ebp), %bx /*arg, 8 because %ebp takes 4 bytes, return address takes 4 bytes*/
	movl 10(%ebp), %edi /*arg, 10 because %ebp takes 4 bytes, return address takes 4 bytes, and input location takes 2 bytes*/
	movl NEXT(%edi), %esi 

	cmpw $LOCATION_BOUND, %bx
	ja search_list_return

search_list_op_loop:
	/*if current is null,
	  function ends*/
	cmpl $0, %esi
	jz search_list_return

	/*compare current location in list with target location
	  if not the same, move to next struct */
	cmpw %bx, LOCATION(%esi)
	jnz search_list_finish_compare

	/*successful search
	  return the pointer pointing to the parent struct*/
	movl %edi, %eax
	popl %edi 
	popl %esi
	popl %ebx
	leave
	ret

search_list_finish_compare:
	/*compare finished, not the same
	  move pointers to the next struct on list*/
	movl NEXT(%esi), %esi
	movl NEXT(%edi), %edi
	jmp search_list_op_loop

search_list_return:
	/*return, function ends
	  pop callee saved variable %ebx, return -1*/
	popl %edi
	popl %esi
	popl %ebx
	movl $-1, %eax
	leave
	ret
.end
