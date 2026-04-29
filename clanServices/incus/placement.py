INSTANCE_LIMIT_PER_MEMBER = 2
PREFERRED_MEMBER_KEY = "user.pu.preferred-member"


def member_count(member_name, project):
    return get_instances_count(project, member_name, True)


def member_has_capacity(member_name, project):
    return member_count(member_name, project) < INSTANCE_LIMIT_PER_MEMBER


def candidate_member(member_name, candidate_members):
    for member in candidate_members:
        if member.server_name == member_name:
            return member
    return None


def preferred_member(request, candidate_members):
    preferred = request.config.get(PREFERRED_MEMBER_KEY, "")
    if preferred == "":
        return ""

    if candidate_member(preferred, candidate_members) == None:
        return ""

    if member_has_capacity(preferred, request.project):
        return preferred

    return ""


def choose_member(request, candidate_members):
    preferred = preferred_member(request, candidate_members)
    if preferred != "":
        return preferred

    best_name = ""
    best_count = 0

    for member in candidate_members:
        count = member_count(member.server_name, request.project)
        if count >= INSTANCE_LIMIT_PER_MEMBER:
            continue

        if best_name == "" or count < best_count or (count == best_count and member.server_name < best_name):
            best_name = member.server_name
            best_count = count

    return best_name


def instance_placement(request, candidate_members):
    if request.reason != "new":
        return

    target = choose_member(request, candidate_members)
    if target == "":
        fail("No Incus cluster member has capacity for another instance (limit: " + str(INSTANCE_LIMIT_PER_MEMBER) + " per member).")

    set_target(target)
