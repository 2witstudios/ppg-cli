using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PPGDesktop.Models;
using PPGDesktop.Services;

namespace PPGDesktop.ViewModels;

public partial class SidebarViewModel : ObservableObject
{
    private readonly PpgApiClient _api;

    [ObservableProperty]
    private ObservableCollection<ProjectNode> _projects = [];

    [ObservableProperty]
    private object? _selectedItem;

    public event Action<WorktreeNode>? WorktreeSelected;
    public event Action<AgentNode>? AgentSelected;

    public SidebarViewModel(PpgApiClient api)
    {
        _api = api;
    }

    public void UpdateFromManifest(Manifest manifest)
    {
        var projectName = System.IO.Path.GetFileName(manifest.ProjectRoot) ?? "Unknown";
        var project = Projects.FirstOrDefault(p => p.ProjectRoot == manifest.ProjectRoot);

        if (project is null)
        {
            project = new ProjectNode(projectName, manifest.ProjectRoot);
            Projects.Add(project);
        }

        project.UpdateWorktrees(manifest.Worktrees);
    }

    public void UpdateFromStatus(StatusResponse status)
    {
        // Find existing project or create placeholder
        var project = Projects.FirstOrDefault();
        if (project is null)
        {
            project = new ProjectNode(status.Session, "");
            Projects.Add(project);
        }

        project.UpdateWorktrees(status.Worktrees);
    }

    public void UpdateAgentStatus(string agentId, string status)
    {
        foreach (var project in Projects)
        {
            foreach (var worktree in project.Worktrees)
            {
                foreach (var agent in worktree.Agents)
                {
                    if (agent.Id == agentId)
                    {
                        agent.Status = status;
                        return;
                    }
                }
            }
        }
    }

    partial void OnSelectedItemChanged(object? value)
    {
        switch (value)
        {
            case WorktreeNode wt:
                WorktreeSelected?.Invoke(wt);
                break;
            case AgentNode agent:
                AgentSelected?.Invoke(agent);
                break;
        }
    }

    [RelayCommand]
    private async Task KillAgentAsync(AgentNode agent)
    {
        await _api.KillAgentAsync(agent.Id);
    }

    [RelayCommand]
    private async Task MergeWorktreeAsync(WorktreeNode worktree)
    {
        await _api.MergeWorktreeAsync(worktree.Id);
    }
}

public partial class ProjectNode : ObservableObject
{
    public string Name { get; }
    public string ProjectRoot { get; }

    [ObservableProperty]
    private ObservableCollection<WorktreeNode> _worktrees = [];

    public ProjectNode(string name, string projectRoot)
    {
        Name = name;
        ProjectRoot = projectRoot;
    }

    public void UpdateWorktrees(Dictionary<string, WorktreeEntry> entries)
    {
        // Update existing or add new
        foreach (var (id, entry) in entries)
        {
            var existing = Worktrees.FirstOrDefault(w => w.Id == id);
            if (existing is not null)
            {
                existing.Update(entry);
            }
            else
            {
                Worktrees.Add(new WorktreeNode(entry));
            }
        }

        // Remove stale
        var toRemove = Worktrees.Where(w => !entries.ContainsKey(w.Id)).ToList();
        foreach (var item in toRemove)
            Worktrees.Remove(item);
    }
}

public partial class WorktreeNode : ObservableObject
{
    public string Id { get; }

    [ObservableProperty]
    private string _name;

    [ObservableProperty]
    private string _branch;

    [ObservableProperty]
    private string _status;

    [ObservableProperty]
    private int _agentCount;

    [ObservableProperty]
    private ObservableCollection<AgentNode> _agents = [];

    public WorktreeNode(WorktreeEntry entry)
    {
        Id = entry.Id;
        _name = entry.Name;
        _branch = entry.Branch;
        _status = entry.Status;
        Update(entry);
    }

    public void Update(WorktreeEntry entry)
    {
        Name = entry.Name;
        Branch = entry.Branch;
        Status = entry.Status;

        // Update agents
        foreach (var (id, agent) in entry.Agents)
        {
            var existing = Agents.FirstOrDefault(a => a.Id == id);
            if (existing is not null)
            {
                existing.Status = agent.Status;
                existing.AgentType = agent.AgentType;
            }
            else
            {
                Agents.Add(new AgentNode(agent, Id));
            }
        }

        var toRemove = Agents.Where(a => !entry.Agents.ContainsKey(a.Id)).ToList();
        foreach (var item in toRemove)
            Agents.Remove(item);

        AgentCount = Agents.Count;
    }
}

public partial class AgentNode : ObservableObject
{
    public string Id { get; }
    public string WorktreeId { get; }

    [ObservableProperty]
    private string _displayName;

    [ObservableProperty]
    private string _agentType;

    [ObservableProperty]
    private string _status;

    [ObservableProperty]
    private string _tmuxTarget;

    public AgentNode(AgentEntry entry, string worktreeId)
    {
        Id = entry.Id;
        WorktreeId = worktreeId;
        _displayName = entry.Name;
        _agentType = entry.AgentType;
        _status = entry.Status;
        _tmuxTarget = entry.TmuxTarget;
    }
}
