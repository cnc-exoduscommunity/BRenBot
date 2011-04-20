<html>

<head>
<title>Server Rankings</title>
<link rel='stylesheet' type='text/css' href='templates/ranks.css'>
</head>

<body>
<center><font size="5">Server Rankings</font>
<if condition="$db">
 <br>Ranks updated every {updateInterval} minutes.<br>
 <font size="2">Ranks last updated {lastUpdate} minutes ago. Next update is in {nextUpdate} minutes.</font>
</if>
<if condition="$updated">
 <br><font size="2">Updating rank data...</font>
</if>
</center><br>

<if condition="$db">
<br><form method='post' action='ranks.php'>
Search for name(s): <input type='text' name='search_name' value='{$searchName}'><br>
Only show players who have played at least 
<select name='gamesPlayed'>
 <!-- BEGIN games_options --><option value='{games_options.value}' {games_options.selected}>{games_options.value}</option><!-- END games_options -->
</select> games.<br>
Order By: 
<select name='orderBy'>
 <!-- BEGIN sort_options --><option value='{sort_options.value}' {sort_options.selected}>{sort_options.name}</option><!-- END sort_options -->
</select>
<input type='submit' value='Go'>
</form><br><br>
</if>

<br>
<br>

<if condition=$player>
<div id='tableContainer' class='tableContainer'>
 <table border='0' cellpadding='0' cellspacing='0' width='100%' class='scrollTable'>
  <thead class='fixedHeader'>
   <tr>
    <th width=70>Rank</th>
    <th width=150>Player Name</th>
    <th width=120>Score (average)</th>
    <th width=120>Kills (average)</th>
    <th width=120>Deaths (average)</th>
    <th width=80>KD Ratio</th>
    <th width=100>MVP Awards</th>
    <th>Games Played</th>
   </tr>
  </thead>
  <tbody class='scrollContent'>

<!-- BEGIN players -->
   <tr>
    <td width=70>{players.rank}</td>
    <td width=150>{players.player}</td>
    <td width=120>{players.score} ({players.spg})</td>
    <td width=120>{players.kills} ({players.kpg})</td>
    <td width=120>{players.deaths} ({players.dpg})</td>
    <td width=80>{players.kd}</td>
    <td width=100>{players.mvp}</td>
    <td>Total: {players.games}<br><font color=yellow>GDI: {players.gdi}</font> &nbsp;&nbsp; <font color=red>Nod: {players.nod}</font></td>
   </tr>
<!-- END PLAYERS -->

  </tbody>
 </table>
</div>

<else>

<center><b>There is no rankings data available at this time! Please check back later</b></center>

</if>